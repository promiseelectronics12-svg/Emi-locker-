const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../../config/database');
const { formatSchedule } = require('../enrollment/enrollmentService');
const sseService = require('../sse/sseService');
const logger = require('../../utils/logger');

const router = express.Router();

async function validateDeviceToken(req, res, next) {
  const token = req.headers['x-device-token'];
  if (!token) return res.status(401).json({ success: false, error: 'Device token required' });

  try {
    const secret = process.env.DEVICE_TOKEN_SECRET;
    if (!secret) {
      logger.error('DEVICE_TOKEN_SECRET not configured');
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    const payload = jwt.verify(token, secret, { algorithms: ['HS256'] });
    if (payload.type !== 'device' || !payload.sub) {
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    req.deviceAuth = payload;
    next();
  } catch (error) {
    logger.warn('Device token validation failed', { error: error.message });
    return res.status(401).json({ success: false, error: 'Invalid device token' });
  }
}

async function loadSchedule(deviceId) {
  const scheduleResult = await db.query(
    `SELECT *
     FROM emi_schedules
     WHERE device_id = $1 AND status = 'active'
     ORDER BY created_at DESC
     LIMIT 1`,
    [deviceId]
  );

  const schedule = scheduleResult.rows[0];
  if (!schedule) return null;

  const paymentsResult = await db.query(
    `SELECT installment_number, payment_status, status
     FROM emi_payments
     WHERE emi_schedule_id = $1
       AND COALESCE(payment_status, status) IN ('completed', 'paid', 'success')
     ORDER BY installment_number`,
    [schedule.id]
  );

  const paid = new Set(
    paymentsResult.rows.map((row) => Number(row.installment_number)).filter(Boolean)
  );
  const formatted = formatSchedule(schedule);
  formatted.installments = formatted.installments.map((installment) => ({
    ...installment,
    status: paid.has(installment.installmentNumber) ? 'PAID' : 'PENDING'
  }));
  return formatted;
}

function parsePermissionHealth(body = {}) {
  const rawStatus = String(body.permission_health || '')
    .trim()
    .toLowerCase();
  const degradedReasons = String(body.permission_degraded_reasons || '')
    .split(',')
    .map((reason) => reason.trim())
    .filter(Boolean)
    .slice(0, 20);

  if (!rawStatus && degradedReasons.length === 0) return null;

  const status = rawStatus === 'degraded' || degradedReasons.length > 0 ? 'degraded' : 'healthy';

  const bool = (key) => String(body[key] || '').toLowerCase() === 'true';

  return {
    status,
    degradedReasons,
    permissions: {
      overlay: bool('permission_overlay'),
      location: bool('permission_location'),
      fineLocation: bool('permission_fine_location'),
      coarseLocation: bool('permission_coarse_location'),
      backgroundLocation: bool('permission_background_location'),
      sms: bool('permission_sms'),
      notifications: bool('permission_notifications'),
      camera: bool('permission_camera'),
      phoneState: bool('permission_phone_state'),
      deviceAdmin: bool('permission_device_admin'),
      deviceOwner: bool('permission_device_owner'),
      batteryUnrestricted: bool('permission_battery_unrestricted')
    }
  };
}

function buildHeartbeatSource(source, appVersion, permissionHealth) {
  const parts = [appVersion ? `${source}:${appVersion}` : source];
  if (permissionHealth) {
    const reasonSuffix = permissionHealth.degradedReasons.length
      ? `:${permissionHealth.degradedReasons.join(',')}`
      : '';
    parts.push(`permissions:${permissionHealth.status}${reasonSuffix}`);
  }
  return parts.join('|').slice(0, 255);
}

function extractPermissionSegment(source) {
  return (
    String(source || '')
      .split('|')
      .find((part) => part.startsWith('permissions:')) || ''
  );
}

function connectionStatusFromLastSeen(lastSeenAt) {
  if (!lastSeenAt) return 'never_seen';
  const lastSeenMs = new Date(lastSeenAt).getTime();
  if (!Number.isFinite(lastSeenMs)) return 'never_seen';

  const ageMinutes = (Date.now() - lastSeenMs) / 60000;
  if (ageMinutes >= 150) return 'offline';
  if (ageMinutes >= 75) return 'delayed';
  return 'online';
}

function parseReportedLockState(body = {}) {
  const raw = String(body.current_lock_state || body.lock_state || '')
    .trim()
    .toUpperCase();
  if (!raw) return null;
  const source = String(body.lock_state_source || body.source || 'user_app').slice(0, 64);

  if (raw === 'NORMAL' && source.startsWith('decouple_command')) {
    return {
      raw,
      source,
      status: 'decoupled',
      lockLevel: 'NONE',
      event: 'decoupled'
    };
  }

  const stateMap = {
    NORMAL: { status: 'enrolled', lockLevel: 'NONE', event: 'unlocked' },
    REMINDER: { status: 'reminder', lockLevel: 'SOFT', event: 'locked' },
    WARNING: { status: 'reminder', lockLevel: 'SOFT', event: 'locked' },
    OVERDUE_ALERT: { status: 'reminder', lockLevel: 'SOFT', event: 'locked' },
    PARTIAL_LOCK: { status: 'partial_lock', lockLevel: 'SOFT', event: 'locked' },
    FULL_LOCK: { status: 'locked', lockLevel: 'FULL', event: 'locked' }
  };

  const mapped = stateMap[raw];
  if (!mapped) return null;

  return {
    raw,
    source,
    ...mapped
  };
}

function hasLockStateChanged(previousDevice, reportedLockState) {
  if (!previousDevice || !reportedLockState) return false;
  return (
    String(previousDevice.status || '') !== reportedLockState.status ||
    String(previousDevice.lock_level || 'NONE') !== reportedLockState.lockLevel
  );
}

router.get('/emi-schedule', validateDeviceToken, async (req, res) => {
  try {
    const schedule = await loadSchedule(req.deviceAuth.sub);
    return res.json({ success: true, emi_schedule: schedule });
  } catch (error) {
    logger.error('Device schedule refresh failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to load EMI schedule' });
  }
});

router.post('/heartbeat', validateDeviceToken, async (req, res) => {
  try {
    const source = String(req.body?.source || 'user_app').slice(0, 64);
    const appVersion = String(req.body?.app_version || '').slice(0, 64);
    const permissionHealth = parsePermissionHealth(req.body);
    const reportedLockState = parseReportedLockState(req.body);
    const healthStatus = permissionHealth?.status === 'degraded' ? 'degraded' : 'online';
    const heartbeatSource = buildHeartbeatSource(source, appVersion, permissionHealth);

    const previous = await db.query(
      `SELECT id, dealer_id, device_name, imei, status, lock_level, lock_reason, last_seen_at,
              device_health_status, last_heartbeat_source
       FROM devices
       WHERE id = $1`,
      [req.deviceAuth.sub]
    );

    const previousDevice = previous.rows[0] || null;
    const previousConnectionStatus = connectionStatusFromLastSeen(previousDevice?.last_seen_at);
    const result = await db.query(
      `UPDATE devices
       SET last_seen_at = NOW(),
           last_heartbeat_source = $2,
           device_health_status = $3,
           fcm_token_status = CASE WHEN fcm_token IS NULL THEN fcm_token_status ELSE 'valid' END,
           app_uninstall_suspected_at = NULL,
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, dealer_id, device_name, imei, last_seen_at, device_health_status, last_heartbeat_source`,
      [req.deviceAuth.sub, heartbeatSource, healthStatus]
    );

    const updatedDevice = result.rows[0];
    let lockStateDevice = updatedDevice;
    const lockStateChanged = hasLockStateChanged(previousDevice, reportedLockState);
    if (reportedLockState) {
      const lockUpdate = await db.query(
        `UPDATE devices
         SET status = $2,
             lock_level = $3,
             lock_reason = CASE WHEN $3 = 'NONE' THEN NULL ELSE COALESCE(lock_reason, 'DEVICE_REPORTED') END,
             locked_at = CASE
               WHEN $3 = 'NONE' THEN NULL
               WHEN locked_at IS NULL THEN NOW()
               ELSE locked_at
             END,
             last_heartbeat_source = LEFT(CONCAT($4::text, '|lock_state:', $5::text), 255),
             updated_at = NOW()
         WHERE id = $1
         RETURNING id, dealer_id, device_name, imei, status, lock_level, lock_reason, locked_at,
                   last_seen_at, device_health_status, last_heartbeat_source`,
        [
          req.deviceAuth.sub,
          reportedLockState.status,
          reportedLockState.lockLevel,
          heartbeatSource,
          `${reportedLockState.raw}:${reportedLockState.source}`
        ]
      );
      lockStateDevice = lockUpdate.rows[0] || updatedDevice;
    }

    const previousPermissionSegment = extractPermissionSegment(
      previousDevice?.last_heartbeat_source
    );
    const nextPermissionSegment = extractPermissionSegment(lockStateDevice?.last_heartbeat_source);
    const nextConnectionStatus = connectionStatusFromLastSeen(lockStateDevice?.last_seen_at);
    if (
      lockStateDevice &&
      (previousConnectionStatus !== nextConnectionStatus ||
        previousDevice?.device_health_status !== lockStateDevice.device_health_status ||
        previousPermissionSegment !== nextPermissionSegment)
    ) {
      sseService.emitDeviceHealthChanged(lockStateDevice, {
        connectionStatus: nextConnectionStatus,
        permissionHealth: permissionHealth?.permissions || null,
        degradedReasons: permissionHealth?.degradedReasons || []
      });
    }

    if (reportedLockState && lockStateDevice) {
      if (reportedLockState.event === 'decoupled') {
        const payload = {
          deviceId: lockStateDevice.id,
          deviceName: lockStateDevice.device_name,
          imei: lockStateDevice.imei,
          status: 'decoupled',
          decoupledAt: new Date().toISOString()
        };
        sseService.pushToManagement('device_decoupled', payload);
        if (lockStateDevice.dealer_id) {
          sseService.pushToDealer(lockStateDevice.dealer_id, 'device_decoupled', payload);
        }
      } else if (reportedLockState.event === 'unlocked') {
        sseService.emitDeviceUnlocked(lockStateDevice, null);
      } else if (lockStateChanged) {
        sseService.emitDeviceLocked(lockStateDevice);
      } else {
        sseService.emitDeviceHealthChanged(lockStateDevice, {
          status: lockStateDevice.device_health_status,
          lockState: reportedLockState.raw
        });
      }
    }

    return res.json({ success: true, server_time: new Date().toISOString() });
  } catch (error) {
    logger.error('Device heartbeat failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to record heartbeat' });
  }
});

module.exports = router;
