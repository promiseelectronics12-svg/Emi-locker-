const db = require('../../config/database');
const logger = require('../../utils/logger');
const lockVerificationService = require('./lockVerificationService');
const lockCommandService = require('./lockCommandService');
const lockDeliveryService = require('./lockDeliveryService');
const locationScheduler = require('../location/locationScheduler');
const pautService = require('./pautService');
const padtService = require('./padtService');
const sseService = require('../sse/sseService');

const LOCK_LEVELS = {
  NONE: 'NONE',
  REMINDER_MODE: 'REMINDER_MODE',
  FULL_LOCK: 'FULL_LOCK',
};

class LockService {
  async requestLock({ deviceId, dealerId, reason, note }) {
    const dealerIdentity = await this.resolveDealerIdentity(dealerId);
    const verification = await lockVerificationService.verifyLockRequest({
      deviceId,
      dealerId: dealerIdentity.dealerRecordId,
      dealerUserId: dealerIdentity.dealerUserId,
      dealerIds: dealerIdentity.dealerIds,
      reason,
      note,
    });

    if (!verification.valid) {
      await this.logAuditEvent({
        actor: dealerIdentity.dealerUserId,
        action: 'LOCK_REQUEST',
        deviceId,
        metadata: { reason, note, decision: verification.decision, failures: verification.failures },
        result: 'rejected',
      });

      return {
        status: verification.decision,
        decision: verification.decision,
        failures: verification.failures,
      };
    }

    const lockLevel = this.determineLockLevel(reason);
    const dbLockLevel = this.toDbLockLevel(lockLevel);
    const dbStatus = this.toDbStatus(lockLevel);
    const currentState = await db.query(
      `SELECT lock_level, status FROM devices WHERE id = $1`,
      [deviceId]
    );
    const currentLockLevel = currentState.rows[0]?.lock_level || 'NONE';
    const currentStatus = String(currentState.rows[0]?.status || '').toLowerCase();
    const alreadyLocked =
      currentLockLevel === 'FULL' ||
      currentLockLevel === 'SOFT' ||
      currentStatus === 'locked' ||
      currentStatus === 'partial_lock' ||
      currentStatus === 'reminder' ||
      currentStatus === 'pending_unlock';

    if (alreadyLocked) {
      return {
        status: 'ALREADY_LOCKED',
        decision: 'ALREADY_LOCKED',
        message: 'Device is already locked. Unlock it before sending another lock command.',
        currentLockLevel,
        currentStatus,
      };
    }

    const requestId = await lockVerificationService.recordApprovedRequest(
      dealerIdentity.dealerRecordId,
      deviceId,
      reason,
      note,
      dealerIdentity.dealerUserId
    );

    const command = await lockCommandService.generateSignedCommand({
      deviceImei: await this.getDeviceImei(deviceId),
      actionType: 'LOCK',
      lockLevel,
      metadata: { reason, dealerId: dealerIdentity.dealerRecordId, requestedBy: dealerIdentity.dealerUserId, requestId },
    });

    const delivery = await lockDeliveryService.deliverCommand(deviceId, command, lockLevel);

    await db.query(
      `UPDATE devices
       SET lock_level = $1, status = $2, lock_reason = $3, locked_at = NOW(), locked_by = $4, updated_at = NOW()
       WHERE id = $5`,
      [dbLockLevel, dbStatus, reason, dealerIdentity.dealerUserId, deviceId]
    );

    const updatedDevice = await this.getDeviceForSse(deviceId);
    if (updatedDevice) {
      sseService.emitDeviceLocked(updatedDevice);
    }

    await locationScheduler.handleDeviceLockChange(deviceId, lockLevel);

    await this.logAuditEvent({
      actor: dealerIdentity.dealerUserId,
      action: 'LOCK_REQUEST',
      deviceId,
      metadata: {
        reason,
        note,
        lockLevel,
        requestId,
        commandNonce: command.nonce,
        delivery: delivery.results,
      },
      result: 'approved',
    });

    return {
      status: 'APPROVED',
      decision: 'APPROVED',
      requestId,
      lockLevel,
      command: {
        nonce: command.nonce,
        expiresAt: command.expiresAt,
      },
      delivery: delivery.results,
    };
  }

  async resolveDealerIdentity(userOrDealerId) {
    const result = await db.query(
      `SELECT id, user_id FROM dealers WHERE id = $1 OR user_id = $1 LIMIT 1`,
      [userOrDealerId]
    );
    const dealer = result.rows[0];
    const dealerRecordId = dealer?.id || userOrDealerId;
    const dealerUserId = dealer?.user_id || userOrDealerId;
    return {
      dealerRecordId,
      dealerUserId,
      dealerIds: [...new Set([dealerRecordId, dealerUserId].filter(Boolean))],
    };
  }

  async generateCommand({ deviceImei, actionType, lockLevel, metadata }) {
    const command = await lockCommandService.generateSignedCommand({
      deviceImei,
      actionType,
      lockLevel,
      metadata,
    });

    await this.logAuditEvent({
      actor: 'system',
      action: 'GENERATE_COMMAND',
      deviceId: null,
      metadata: { deviceImei, actionType, lockLevel, nonce: command.nonce },
      result: 'success',
    });

    return command;
  }

  async issuePaut({ deviceId, imei, lockLevel }) {
    const device = await db.query(
      `SELECT id, imei, status FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (device.rows.length === 0) {
      throw new Error('Device not found');
    }

    const result = await pautService.issueToken({
      deviceId,
      imei: imei || device.rows[0].imei,
      lockLevel: lockLevel || 'FULL_LOCK',
    });

    await this.logAuditEvent({
      actor: 'system',
      action: 'ISSUE_PAUT',
      deviceId,
      metadata: { jti: result.jti, lockLevel: result.lockLevel },
      result: 'success',
    });

    return result;
  }

  async issuePadt({ deviceId, imei, ownerId, dealerId }) {
    const device = await db.query(
      `SELECT id, imei, owner_id, dealer_id, status FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (device.rows.length === 0) {
      throw new Error('Device not found');
    }

    const result = await padtService.issueToken({
      deviceId,
      imei: imei || device.rows[0].imei,
      ownerId: ownerId || device.rows[0].owner_id,
      dealerId: dealerId || device.rows[0].dealer_id,
    });

    await this.logAuditEvent({
      actor: 'system',
      action: 'ISSUE_PADT',
      deviceId,
      metadata: { jti: result.jti },
      result: 'success',
    });

    return result;
  }

  async getDeviceLockStatus(deviceId) {
    const device = await db.query(
      `SELECT d.id, d.imei, d.status, d.lock_level, d.lock_reason, d.locked_at, d.locked_by,
              d.device_name, d.model, d.brand
       FROM devices d
       WHERE d.id = $1`,
      [deviceId]
    );

    if (device.rows.length === 0) {
      throw new Error('Device not found');
    }

    const d = device.rows[0];

    const recentRequests = await db.query(
      `SELECT id, reason_code, status, created_at FROM lock_requests
       WHERE device_id = $1 ORDER BY created_at DESC LIMIT 10`,
      [deviceId]
    );

    return {
      deviceId: d.id,
      imei: d.imei,
      deviceName: d.device_name,
      model: d.model,
      brand: d.brand,
      status: d.status,
      lockLevel: d.lock_level || 'NONE',
      lockReason: d.lock_reason,
      lockedAt: d.locked_at,
      lockedBy: d.locked_by,
      recentRequests: recentRequests.rows,
    };
  }

  async getDealerLockRequests(dealerId, { page = 1, limit = 20 } = {}) {
    const offset = (page - 1) * limit;

    const result = await db.query(
      `SELECT lr.id, lr.device_id, lr.reason_code, lr.note, lr.status, lr.rejection_reasons, lr.created_at,
              d.imei, d.device_name, d.model, d.brand
       FROM lock_requests lr
       LEFT JOIN devices d ON lr.device_id = d.id
       WHERE lr.dealer_id = $1
       ORDER BY lr.created_at DESC
       LIMIT $2 OFFSET $3`,
      [dealerId, limit, offset]
    );

    const countResult = await db.query(
      `SELECT COUNT(*) as total FROM lock_requests WHERE dealer_id = $1`,
      [dealerId]
    );

    return {
      requests: result.rows,
      pagination: {
        page,
        limit,
        total: parseInt(countResult.rows[0].total, 10),
        pages: Math.ceil(parseInt(countResult.rows[0].total, 10) / limit),
      },
    };
  }

  determineLockLevel(reason) {
    const levelMap = {
      EMI_OVERDUE: LOCK_LEVELS.FULL_LOCK,
      DEVICE_STOLEN: LOCK_LEVELS.FULL_LOCK,
      TERMS_VIOLATION: LOCK_LEVELS.FULL_LOCK,
      SUSPECTED_FRAUD: LOCK_LEVELS.REMINDER_MODE,
      SUSPECTED_SALE: LOCK_LEVELS.REMINDER_MODE,
    };
    return levelMap[reason] || LOCK_LEVELS.FULL_LOCK;
  }

  toDbLockLevel(lockLevel) {
    if (lockLevel === LOCK_LEVELS.FULL_LOCK) return 'FULL';
    if (lockLevel === LOCK_LEVELS.REMINDER_MODE) return 'SOFT';
    return 'NONE';
  }

  toDbStatus(lockLevel) {
    if (lockLevel === LOCK_LEVELS.FULL_LOCK) return 'locked';
    if (lockLevel === LOCK_LEVELS.REMINDER_MODE) return 'reminder';
    return 'enrolled';
  }

  async requestUnlock({ deviceId, actorId, actorRole }) {
    const device = await db.query(
      `SELECT id, imei, lock_level FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (device.rows.length === 0) {
      throw new Error('Device not found');
    }

    if (device.rows[0].lock_level === 'NONE') {
      return {
        status: 'NO_LOCK',
        decision: 'NO_LOCK',
        message: 'Device is not locked',
      };
    }

    const command = await lockCommandService.generateSignedCommand({
      deviceImei: device.rows[0].imei,
      actionType: 'UNLOCK',
      lockLevel: LOCK_LEVELS.NONE,
      metadata: { actorId, actorRole, source: 'unlock_request' },
    });

    const delivery = await lockDeliveryService.deliverCommand(deviceId, command, LOCK_LEVELS.NONE);

    await db.query(
      `UPDATE devices
       SET lock_level = $1, status = $2, lock_reason = NULL, locked_at = NULL, locked_by = NULL, updated_at = NOW()
       WHERE id = $3`,
      ['NONE', 'enrolled', deviceId]
    );

    const updatedDevice = await this.getDeviceForSse(deviceId);
    if (updatedDevice) {
      sseService.emitDeviceUnlocked(updatedDevice, null);
    }

    await locationScheduler.handleDeviceLockChange(deviceId, LOCK_LEVELS.NONE);

    await this.logAuditEvent({
      actor: actorId,
      action: 'UNLOCK_REQUEST',
      deviceId,
      metadata: {
        commandNonce: command.nonce,
        delivery: delivery.results,
        previousLockLevel: device.rows[0].lock_level,
      },
      result: 'approved',
    });

    return {
      status: 'APPROVED',
      decision: 'APPROVED',
      lockLevel: LOCK_LEVELS.NONE,
      command: {
        nonce: command.nonce,
        expiresAt: command.expiresAt,
      },
      delivery: delivery.results,
    };
  }

  async getDeviceImei(deviceId) {
    const result = await db.query(
      `SELECT imei FROM devices WHERE id = $1`,
      [deviceId]
    );
    if (result.rows.length === 0) {
      throw new Error('Device not found');
    }
    return result.rows[0].imei;
  }

  async getDeviceForSse(deviceId) {
    const result = await db.query(
      `SELECT id, imei, device_name, amapi_device_name, dealer_id, lock_level, lock_reason, locked_at
       FROM devices
       WHERE id = $1`,
      [deviceId]
    );
    const device = result.rows[0];
    if (!device) return null;
    return {
      ...device,
      device_name: device.device_name || device.amapi_device_name || device.imei,
    };
  }

  async logAuditEvent({ actor, action, deviceId, metadata, result }) {
    try {
      await db.query(
        `INSERT INTO audit_log (actor, action, device_id, metadata, result, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [actor, action, deviceId, JSON.stringify(metadata), result]
      );
    } catch (error) {
      logger.error('Failed to write audit log', { error: error.message });
    }
  }
}

module.exports = new LockService();
