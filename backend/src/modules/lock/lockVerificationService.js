const db = require('../../config/database');
const logger = require('../../utils/logger');

const LOCK_LEVELS = {
  NONE: 'NONE',
  REMINDER_MODE: 'REMINDER_MODE',
  FULL_LOCK: 'FULL_LOCK',
};

const LOCK_LEVEL_HIERARCHY = {
  [LOCK_LEVELS.NONE]: 0,
  [LOCK_LEVELS.REMINDER_MODE]: 1,
  [LOCK_LEVELS.FULL_LOCK]: 2,
};

const VALID_LOCK_REASONS = [
  'EMI_OVERDUE',
  'SUSPECTED_FRAUD',
  'SUSPECTED_SALE',
  'DEVICE_STOLEN',
  'TERMS_VIOLATION',
];

const ESCALATION_REASONS = ['SUSPECTED_FRAUD', 'SUSPECTED_SALE'];

const GRACE_PERIOD_DAYS = parseInt(process.env.GRACE_PERIOD_DAYS, 10) || 7;
const MAX_INVALID_REQUESTS = 3;
const INVALID_REQUEST_WINDOW_HOURS = 24;
const LOCK_ABUSE_GUARD_ENABLED = process.env.LOCK_ABUSE_GUARD_ENABLED === 'true';
const GPS_RADIUS_METERS = parseInt(process.env.GPS_RADIUS_METERS, 10) || 500;

class LockVerificationService {
  async verifyLockRequest({ deviceId, dealerId, dealerUserId, dealerIds, reason, note }) {
    const failures = [];

    const device = await this.getDeviceWithEmi(deviceId, dealerIds);
    if (!device) {
      return { valid: false, decision: 'REJECTED', failures: ['Device not found'] };
    }

    if (device.status === 'decoupled') {
      return { valid: false, decision: 'REJECTED', failures: ['Device is already decoupled'] };
    }

    // Manual dealer locks must work during testing. Payment-state gating belongs
    // in the EMI scheduler/business rules, not in this click path.
    const graceCheck = await this.checkGracePeriodExtension(deviceId);
    if (graceCheck.active) {
      failures.push('Grace period extension is active');
    }

    // During demo/testing, lock requests are idempotent: re-submitting a lock
    // should re-send the command instead of blocking on the current DB state.

    if (LOCK_ABUSE_GUARD_ENABLED) {
      const abuseCheck = await this.checkDealerAbuse(dealerUserId || dealerId);
      if (abuseCheck.abused) {
        failures.push(`Dealer submitted ${abuseCheck.count} invalid requests in the last ${INVALID_REQUEST_WINDOW_HOURS} hours`);
      }
    }

    if (ESCALATION_REASONS.includes(reason)) {
      await this.escalateToAdmin({ deviceId, dealerId, reason, note });
      return {
        valid: false,
        decision: 'ESCALATED',
        failures: [`Reason ${reason} escalated to admin for review`],
      };
    }

    if (failures.length > 0) {
      await this.recordInvalidRequest(dealerId, deviceId, reason, failures, dealerUserId || dealerId);
      return { valid: false, decision: 'REJECTED', failures };
    }

    return { valid: true, decision: 'APPROVED', failures: [] };
  }

  async getDeviceWithEmi(deviceId, dealerIds = null) {
    const ownershipClause = Array.isArray(dealerIds) && dealerIds.length
      ? 'AND d.dealer_id = ANY($2::uuid[])'
      : '';
    const params = Array.isArray(dealerIds) && dealerIds.length
      ? [deviceId, dealerIds]
      : [deviceId];
    const result = await db.query(
      `SELECT d.*, es.start_date as next_due_date, es.total_amount as total_emi_amount,
              COALESCE((SELECT SUM(amount) FROM emi_payments WHERE emi_schedule_id = es.id AND status = 'completed'), 0) as paid_amount,
              es.start_date, (es.start_date + (es.duration || ' months')::INTERVAL) as emi_end_date,
              es.duration as installments_total,
              (SELECT COUNT(*) FROM emi_payments WHERE emi_schedule_id = es.id AND status = 'completed') as installments_paid,
              es.grace_days as grace_period_days
       FROM devices d
       LEFT JOIN emi_schedules es ON d.id = es.device_id AND es.status = 'active'
       WHERE d.id = $1 ${ownershipClause}`,
      params
    );
    return result.rows[0] || null;
  }

  async checkEmiPaymentStatus(device) {
    if (!device.next_due_date) {
      return { current: true, overdueDays: 0 };
    }

    const now = new Date();
    const dueDate = new Date(device.next_due_date);
    const graceDays = device.grace_period_days || GRACE_PERIOD_DAYS;
    const graceEnd = new Date(dueDate);
    graceEnd.setDate(graceEnd.getDate() + graceDays);

    if (now <= graceEnd) {
      return { current: true, overdueDays: 0 };
    }

    const overdueDays = Math.floor((now - dueDate) / (1000 * 60 * 60 * 24));
    return { current: false, overdueDays };
  }

  async checkGracePeriodExtension(deviceId) {
    const result = await db.query(
      `SELECT id, granted_until, reason
       FROM grace_period_extensions
       WHERE device_id = $1 AND granted_until > NOW() AND status = 'active'
       ORDER BY granted_until DESC LIMIT 1`,
      [deviceId]
    );

    if (result.rows.length > 0) {
      return { active: true, extension: result.rows[0] };
    }
    return { active: false };
  }

  checkDeviceLockLevel(device, reason) {
    const normalizedCurrent = this.normalizeLockLevel(device.lock_level);
    const currentLevel = LOCK_LEVEL_HIERARCHY[normalizedCurrent] || 0;

    const reasonToLevel = {
      EMI_OVERDUE: LOCK_LEVELS.FULL_LOCK,
      DEVICE_STOLEN: LOCK_LEVELS.FULL_LOCK,
      TERMS_VIOLATION: LOCK_LEVELS.FULL_LOCK,
      SUSPECTED_FRAUD: LOCK_LEVELS.REMINDER_MODE,
      SUSPECTED_SALE: LOCK_LEVELS.REMINDER_MODE,
    };

    const requestedLevel = LOCK_LEVEL_HIERARCHY[reasonToLevel[reason] || LOCK_LEVELS.FULL_LOCK];

    return {
      alreadyAtOrHigher: currentLevel >= requestedLevel,
      currentLevel: Object.keys(LOCK_LEVEL_HIERARCHY).find(k => LOCK_LEVEL_HIERARCHY[k] === currentLevel) || 'NONE',
      requestedLevel: Object.keys(LOCK_LEVEL_HIERARCHY).find(k => LOCK_LEVEL_HIERARCHY[k] === requestedLevel) || 'FULL_LOCK',
    };
  }

  normalizeLockLevel(lockLevel) {
    const aliases = {
      NONE: LOCK_LEVELS.NONE,
      SOFT: LOCK_LEVELS.REMINDER_MODE,
      FULL: LOCK_LEVELS.FULL_LOCK,
      WIPE: LOCK_LEVELS.FULL_LOCK,
      REMINDER_MODE: LOCK_LEVELS.REMINDER_MODE,
      PARTIAL_LOCK: LOCK_LEVELS.REMINDER_MODE,
      FULL_LOCK: LOCK_LEVELS.FULL_LOCK,
    };
    return aliases[lockLevel] || LOCK_LEVELS.NONE;
  }

  async checkDealerAbuse(dealerId) {
    const result = await db.query(
      `SELECT COUNT(*) as count
       FROM lock_requests
       WHERE requested_by = $1
         AND status = 'rejected'
         AND created_at > NOW() - ($2 || ' hours')::interval`,
      [dealerId, INVALID_REQUEST_WINDOW_HOURS]
    );

    const count = parseInt(result.rows[0].count, 10);
    return { abused: count >= MAX_INVALID_REQUESTS, count };
  }

  async checkDeviceGpsAtShop(deviceId, dealerId, reason) {
    const deviceGps = await db.query(
      `SELECT latitude, longitude, recorded_at FROM location_reports
       WHERE device_id = $1 ORDER BY timestamp DESC LIMIT 1`,
      [deviceId]
    );

    if (deviceGps.rows.length === 0) {
      return { atShop: false };
    }

    const dealer = await db.query(
      `SELECT shop_latitude, shop_longitude FROM dealers WHERE id = $1`,
      [dealerId]
    );

    if (dealer.rows.length === 0 || !dealer.rows[0].shop_latitude) {
      return { atShop: false };
    }

    const { latitude, longitude } = deviceGps.rows[0];
    const { shop_latitude, shop_longitude } = dealer.rows[0];

    const distance = this.calculateDistance(latitude, longitude, shop_latitude, shop_longitude);

    return { atShop: distance <= GPS_RADIUS_METERS, distance };
  }

  calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371e3;
    const toRad = (deg) => (deg * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  async recordInvalidRequest(dealerId, deviceId, reason, failures, requestedBy = dealerId) {
    const reasonCodeMap = {
      'EMI_OVERDUE': 'emi_default',
      'SUSPECTED_FRAUD': 'fraud_detected',
      'SUSPECTED_SALE': 'other',
      'DEVICE_STOLEN': 'stolen_report',
      'TERMS_VIOLATION': 'policy_violation',
    };
    const reasonCode = reasonCodeMap[reason] || 'other';
    await db.query(
      `INSERT INTO lock_requests (dealer_id, requested_by, device_id, reason_code, note, status, rejection_reasons, created_at)
       VALUES ($1, $6, $2, $3, $4, 'rejected', $5, NOW())`,
      [dealerId, deviceId, reasonCode, null, JSON.stringify(failures), requestedBy]
    );
  }

  async escalateToAdmin({ deviceId, dealerId, reason, note }) {
    await db.query(
      `INSERT INTO admin_escalations (entity_type, entity_id, dealer_id, reason, note, status, created_at)
       VALUES ('device', $1, $2, $3, $4, 'pending', NOW())`,
      [deviceId, dealerId, reason, note || null]
    );

    logger.warn('Lock request escalated to admin', { deviceId, dealerId, reason });
  }

  async recordApprovedRequest(dealerId, deviceId, reason, note, requestedBy = dealerId) {
    const reasonCodeMap = {
      'EMI_OVERDUE': 'emi_default',
      'SUSPECTED_FRAUD': 'fraud_detected',
      'SUSPECTED_SALE': 'other',
      'DEVICE_STOLEN': 'stolen_report',
      'TERMS_VIOLATION': 'policy_violation',
    };
    const reasonCode = reasonCodeMap[reason] || 'other';
    const result = await db.query(
      `INSERT INTO lock_requests (dealer_id, requested_by, device_id, reason_code, note, status, created_at)
       VALUES ($1, $5, $2, $3, $4, 'approved', NOW())
       RETURNING id`,
      [dealerId, deviceId, reasonCode, note || null, requestedBy]
    );
    return result.rows[0].id;
  }

  getAutoLockLevel(overdueDays) {
    if (overdueDays <= -7) return { level: LOCK_LEVELS.NONE, action: 'REMINDER_PUSH' };
    if (overdueDays <= -3) return { level: LOCK_LEVELS.NONE, action: 'WARNING_OVERLAY' };
    if (overdueDays <= 0) return { level: LOCK_LEVELS.NONE, action: 'OVERDUE_ALERT' };
    if (overdueDays <= 1) return { level: LOCK_LEVELS.REMINDER_MODE, action: 'APPLY_LOCK' };
    if (overdueDays <= 3) return { level: LOCK_LEVELS.REMINDER_MODE, action: 'APPLY_LOCK' };
    if (overdueDays <= 7) return { level: LOCK_LEVELS.FULL_LOCK, action: 'APPLY_LOCK' };
    return { level: LOCK_LEVELS.FULL_LOCK, action: 'APPLY_LOCK_ADMIN_FLAG' };
  }

  getLockLevelHierarchy() {
    return LOCK_LEVEL_HIERARCHY;
  }
}

module.exports = new LockVerificationService();
module.exports.LOCK_LEVELS = LOCK_LEVELS;
module.exports.LOCK_LEVEL_HIERARCHY = LOCK_LEVEL_HIERARCHY;
module.exports.VALID_LOCK_REASONS = VALID_LOCK_REASONS;
