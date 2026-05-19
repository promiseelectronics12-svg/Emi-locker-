const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../../config/database');
const { formatSchedule } = require('../enrollment/enrollmentService');
const sseService = require('../sse/sseService');
const logger = require('../../utils/logger');
const { getActiveAssignment } = require('../assignments/assignmentService');
const deviceProfileService = require('../profile/deviceProfileService');
const dealerNotificationService = require('../notifications/dealerNotificationService');
const { riskService } = require('../risk');

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

    // Verify device still exists and is in an active state
    const deviceResult = await db.query(
      `SELECT id, status FROM devices WHERE id = $1 LIMIT 1`,
      [payload.sub]
    );
    if (!deviceResult.rows.length) {
      return res.status(401).json({ success: false, error: 'Device not found' });
    }
    const deviceStatus = deviceResult.rows[0].status;
    const blockedStatuses = ['decommissioned', 'stolen', 'suspended', 'decoupled'];
    if (blockedStatuses.includes(deviceStatus)) {
      return res.status(403).json({ success: false, error: 'Device access revoked' });
    }

    req.deviceAuth = { ...payload, deviceStatus };
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
    PARTIAL_LOCK: { status: 'reminder', lockLevel: 'SOFT', event: 'locked' },
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

function lockLevelRank(level) {
  const value = String(level || 'NONE').toUpperCase();
  if (value === 'FULL') return 2;
  if (value === 'SOFT') return 1;
  return 0;
}

function shouldApplyReportedLockState(previousDevice, reportedLockState) {
  if (!reportedLockState) return false;
  const previousStatus = String(previousDevice?.status || '').toLowerCase();

  if (previousStatus === 'decoupled') {
    return reportedLockState.event === 'decoupled';
  }

  if (previousStatus === 'pending_decouple' && reportedLockState.event !== 'decoupled') {
    return false;
  }

  if (reportedLockState.lockLevel === 'NONE') {
    return true;
  }

  const previousRank = lockLevelRank(previousDevice?.lock_level);
  const reportedRank = lockLevelRank(reportedLockState.lockLevel);

  if (previousStatus === 'locked' && reportedRank < previousRank) {
    return false;
  }

  return true;
}

function haversineMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function safeSse(methodName, args, fallback) {
  try {
    const emitter = sseService[methodName];
    if (typeof emitter === 'function') {
      emitter(...args);
      return;
    }
    logger.warn('SSE emitter unavailable', { methodName });
    if (typeof fallback === 'function') fallback();
  } catch (error) {
    logger.warn('SSE emit failed', { methodName, error: error.message });
  }
}

function emitDeviceHealthBestEffort(device, health = {}) {
  safeSse('emitDeviceHealthChanged', [device, health], () => {
    const payload = {
      deviceId: device.id,
      deviceName: device.device_name,
      imei: device.imei,
      healthStatus: device.device_health_status || health.status || 'unknown',
      permissionHealth: health.permissionHealth || null,
      degradedReasons: health.degradedReasons || [],
      lastSeenAt: device.last_seen_at || new Date().toISOString(),
      changedAt: new Date().toISOString()
    };
    safeSse('pushToManagement', ['device_health_changed', payload]);
    if (device.dealer_id) {
      safeSse('pushToDealer', [device.dealer_id, 'device_health_changed', payload]);
    }
  });
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

    const reportedSimPhone = req.body?.sim_phone_number
      ? String(req.body.sim_phone_number).slice(0, 20)
      : null;
    const reportedLat = parseFloat(req.body?.lat);
    const reportedLng = parseFloat(req.body?.lng);
    const reportedAccuracy = parseFloat(req.body?.gps_accuracy);
    const hasLocation =
      Number.isFinite(reportedLat) &&
      Number.isFinite(reportedLng) &&
      reportedLat >= -90 && reportedLat <= 90 &&
      reportedLng >= -180 && reportedLng <= 180;

    const previous = await db.query(
      `SELECT d.id, d.dealer_id, d.device_name, d.imei, d.status, d.lock_level, d.lock_reason,
              d.last_seen_at, d.device_health_status, d.last_heartbeat_source,
              d.registered_phone, d.sim_missing_since, d.locked_at,
              dl.name AS dealer_name,
              COALESCE(NULLIF(d.dealer_phone, ''), dl.phone) AS dealer_phone
       FROM devices d
       LEFT JOIN dealers dl ON dl.id = d.dealer_id
       WHERE d.id = $1`,
      [req.deviceAuth.sub]
    );

    const previousDevice = previous.rows[0] || null;
    const previousConnectionStatus = connectionStatusFromLastSeen(previousDevice?.last_seen_at);

    // SIM change / absence detection
    const deviceId = req.deviceAuth.sub;
    const assignmentId = await getActiveAssignment(deviceId);

    if (previousDevice?.registered_phone) {
      if (!reportedSimPhone) {
        // SIM absent — start or maintain the missing timer
        if (!previousDevice.sim_missing_since) {
          await db.query(
            `UPDATE devices SET sim_missing_since = NOW(), updated_at = NOW() WHERE id = $1`,
            [deviceId]
          );
          dealerNotificationService.notifySimRemoved(previousDevice, {
            oldPhone: previousDevice.registered_phone,
            wrongSim: false
          }).catch((error) => logger.warn('Dealer SIM-missing notification failed', {
            deviceId,
            error: error.message
          }));
        }
      } else if (reportedSimPhone === previousDevice.registered_phone) {
        // Bound SIM restored — clear the missing timer and risk signal (fix #6)
        if (previousDevice.sim_missing_since) {
          await db.query(
            `UPDATE devices SET sim_missing_since = NULL, updated_at = NOW() WHERE id = $1`,
            [deviceId]
          );
          riskService.removeSignal(deviceId, 'sim_missing').catch(() => {});
        }
      } else {
        // Wrong SIM — bound SIM is still absent; start or maintain the missing timer
        if (!previousDevice.sim_missing_since) {
          await db.query(
            `UPDATE devices SET sim_missing_since = NOW(), updated_at = NOW() WHERE id = $1`,
            [deviceId]
          );
        }
        // Record the SIM change event
        await db.query(
          `INSERT INTO sim_events (device_id, assignment_id, event_type, old_sim_hash, new_sim_hash, location_lat, location_lon)
           VALUES ($1, $2, 'SIM_CHANGED', $3, $4, $5, $6)`,
          [
            deviceId, assignmentId,
            previousDevice.registered_phone, reportedSimPhone,
            hasLocation ? reportedLat : null,
            hasLocation ? reportedLng : null
          ]
        );
        await db.query(
          `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, permanent, details)
           VALUES ($1, $2, 'SIM_CHANGED', 'device', true, $3)`,
          [
            deviceId, assignmentId,
            JSON.stringify({ old_phone: previousDevice.registered_phone, new_phone: reportedSimPhone })
          ]
        );
        if (previousDevice.dealer_id) {
          safeSse('pushToDealer', [
            previousDevice.dealer_id,
            'sim_changed',
            {
              deviceId,
              deviceName: previousDevice.device_name,
              imei: previousDevice.imei,
              oldPhone: previousDevice.registered_phone,
              newPhone: reportedSimPhone
            }
          ]);
        }
        dealerNotificationService.notifySimRemoved(previousDevice, {
          oldPhone: previousDevice.registered_phone,
          newPhone: reportedSimPhone,
          wrongSim: true
        }).catch((error) => logger.warn('Dealer wrong-SIM notification failed', {
          deviceId,
          error: error.message
        }));
        logger.info('SIM change detected on heartbeat', { deviceId });
      }
    }

    // Location capture — store only if moved >100m from last known point
    if (hasLocation) {
      const lastLoc = await db.query(
        `SELECT latitude, longitude FROM location_reports
         WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 1`,
        [req.deviceAuth.sub]
      );
      const last = lastLoc.rows[0];
      const shouldStore =
        !last ||
        haversineMeters(last.latitude, last.longitude, reportedLat, reportedLng) > 100;
      if (shouldStore) {
        await db.query(
          `INSERT INTO location_reports
             (device_id, assignment_id, latitude, longitude, accuracy, timestamp, recorded_at, source)
           VALUES ($1, $2, $3, $4, $5, NOW(), NOW(), 'gps')`,
          [
            deviceId, assignmentId,
            reportedLat, reportedLng,
            Number.isFinite(reportedAccuracy) ? reportedAccuracy : null
          ]
        );
      }
    }

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
    const shouldApplyLockState = shouldApplyReportedLockState(previousDevice, reportedLockState);
    const lockStateChanged = shouldApplyLockState && hasLockStateChanged(previousDevice, reportedLockState);
    if (reportedLockState && shouldApplyLockState) {
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
    } else if (reportedLockState && !shouldApplyLockState) {
      logger.info('Ignored weaker device lock heartbeat', {
        deviceId: req.deviceAuth.sub,
        currentStatus: previousDevice?.status,
        currentLockLevel: previousDevice?.lock_level,
        reportedLockState: reportedLockState.raw,
        reportedLockLevel: reportedLockState.lockLevel
      });
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
      emitDeviceHealthBestEffort(lockStateDevice, {
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
        safeSse('pushToManagement', ['device_decoupled', payload]);
        if (lockStateDevice.dealer_id) {
          safeSse('pushToDealer', [lockStateDevice.dealer_id, 'device_decoupled', payload]);
        }
      } else if (reportedLockState.event === 'unlocked') {
        safeSse('emitDeviceUnlocked', [lockStateDevice, null]);
      } else if (lockStateChanged) {
        safeSse('emitDeviceLocked', [lockStateDevice]);
      } else {
        emitDeviceHealthBestEffort(lockStateDevice, {
          status: lockStateDevice.device_health_status,
          lockState: reportedLockState.raw
        });
      }
    }

    // Pending command fallback — catches missed FCM deliveries
    let pendingCommand = null;
    const currentStatus = lockStateDevice?.status || previousDevice?.status;
    if (currentStatus === 'pending_lock') {
      pendingCommand = {
        type: 'LOCK',
        lockLevel: lockStateDevice?.lock_level || 'FULL',
        issuedAt: lockStateDevice?.locked_at || previousDevice?.locked_at
      };
    } else if (currentStatus === 'pending_unlock') {
      pendingCommand = { type: 'UNLOCK', issuedAt: previousDevice?.updated_at };
    } else if (currentStatus === 'pending_decouple') {
      pendingCommand = { type: 'DECOUPLE', issuedAt: previousDevice?.updated_at };
    }

    // Fetch monitoring mode so user app can adapt heartbeat interval
    let currentMode = 'subconscious';
    try {
      const profile = await deviceProfileService.getOrCreate(deviceId);
      currentMode = profile.current_mode;
      // Auto-expire learning mode
      if (currentMode === 'learning' && profile.learning_mode_ends_at &&
          new Date(profile.learning_mode_ends_at) < new Date()) {
        await deviceProfileService.updateMode(deviceId, 'subconscious');
        currentMode = 'subconscious';
      }
    } catch (error) {
      logger.warn('Failed to resolve device monitoring mode', { deviceId, error: error.message });
    }

    return res.json({
      success: true,
      server_time: new Date().toISOString(),
      dealer_name: previousDevice?.dealer_name || null,
      dealer_phone: previousDevice?.dealer_phone || null,
      pending_command: pendingCommand,
      current_mode: currentMode
    });
  } catch (error) {
    logger.error('Device heartbeat failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to record heartbeat' });
  }
});

// SMS heartbeat — dealer app forwards HMAC-signed SMS received from device
router.post('/sms-heartbeat', async (req, res) => {
  try {
    const { raw_sms, sender_phone } = req.body || {};
    if (!raw_sms || !sender_phone) {
      return res.status(400).json({ success: false, error: 'raw_sms and sender_phone required' });
    }

    // Find device by registered_phone matching sender
    const deviceResult = await db.query(
      `SELECT id, dealer_id, device_name, imei, sms_heartbeat_sequence FROM devices
       WHERE registered_phone = $1
         AND status NOT IN ('decoupled', 'decommissioned')
       LIMIT 1`,
      [String(sender_phone).slice(0, 20)]
    );
    if (!deviceResult.rows.length) {
      return res.status(404).json({ success: false, error: 'Device not found for sender' });
    }
    const device = deviceResult.rows[0];

    // Decode and verify HMAC
    let payload;
    try {
      const decoded = Buffer.from(raw_sms.trim(), 'base64').toString('utf8');
      const dotIdx = decoded.lastIndexOf('.');
      if (dotIdx < 0) throw new Error('invalid format');
      const data = decoded.slice(0, dotIdx);
      const sig = decoded.slice(dotIdx + 1);
      const secret = process.env.DEVICE_TOKEN_SECRET;
      if (!secret) throw new Error('secret not configured');
      const expected = require('crypto')
        .createHmac('sha256', secret + device.id)
        .update(data)
        .digest('base64');
      const sigBuf = Buffer.from(sig);
      const expectedBuf = Buffer.from(expected);
      if (
        sigBuf.length !== expectedBuf.length ||
        !require('crypto').timingSafeEqual(sigBuf, expectedBuf)
      ) {
        throw new Error('signature mismatch');
      }
      const parts = data.split('|');
      payload = {
        deviceId: parts[0],
        imei: parts[1],
        timestamp: parts[2],
        lat: parseFloat(parts[3]),
        lng: parseFloat(parts[4]),
        sequence: parseInt(parts[5], 10)
      };
    } catch (e) {
      logger.warn('SMS heartbeat HMAC verification failed', { deviceId: device.id, error: e.message });
      return res.status(400).json({ success: false, error: 'Invalid SMS payload' });
    }

    // Replay attack check
    if (payload.sequence <= (device.sms_heartbeat_sequence || 0)) {
      logger.warn('SMS heartbeat replay detected', { deviceId: device.id, sequence: payload.sequence });
      return res.status(400).json({ success: false, error: 'Stale sequence' });
    }

    // Update device
    await db.query(
      `UPDATE devices SET last_sms_heartbeat_at = NOW(), sms_heartbeat_sequence = $2, updated_at = NOW()
       WHERE id = $1`,
      [device.id, payload.sequence]
    );

    // Store location if valid
    const hasLoc = Number.isFinite(payload.lat) && Number.isFinite(payload.lng);
    if (hasLoc) {
      const lastLoc = await db.query(
        `SELECT latitude, longitude FROM location_reports WHERE device_id = $1 ORDER BY recorded_at DESC LIMIT 1`,
        [device.id]
      );
      const last = lastLoc.rows[0];
      if (!last || haversineMeters(last.latitude, last.longitude, payload.lat, payload.lng) > 100) {
        await db.query(
          `INSERT INTO location_reports
             (device_id, latitude, longitude, accuracy, timestamp, recorded_at, source)
           VALUES ($1, $2, $3, 0, NOW(), NOW(), 'sms_heartbeat')`,
          [device.id, payload.lat, payload.lng]
        );
      }
    }

    const smsAssignmentId = await getActiveAssignment(device.id);
    await db.query(
      `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, details)
       VALUES ($1, $2, 'SMS_HEARTBEAT_RECEIVED', 'device', $3)`,
      [device.id, smsAssignmentId, JSON.stringify({ sequence: payload.sequence, has_location: hasLoc })]
    );

    safeSse('pushToDealer', [device.dealer_id, 'sms_heartbeat', {
      deviceId: device.id, deviceName: device.device_name, imei: device.imei,
      receivedAt: new Date().toISOString()
    }]);

    return res.json({ success: true });
  } catch (error) {
    logger.error('SMS heartbeat failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to process SMS heartbeat' });
  }
});

// Call event — device reports call outcomes from dealer's number
router.post('/call-event', validateDeviceToken, async (req, res) => {
  try {
    const eventType = String(req.body?.event_type || '').toUpperCase();
    if (!['DECLINED', 'ANSWERED', 'MISSED'].includes(eventType)) {
      return res.status(400).json({ success: false, error: 'Invalid event_type' });
    }

    let historyType = 'CALL_MISSED';
    if (eventType === 'DECLINED') {
      historyType = 'CALL_DECLINED';
    } else if (eventType === 'ANSWERED') {
      historyType = 'CALL_ANSWERED';
    }

    const callAssignmentId = await getActiveAssignment(req.deviceAuth.sub);
    await db.query(
      `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, details)
       VALUES ($1, $2, $3, 'device', $4)`,
      [req.deviceAuth.sub, callAssignmentId, historyType, JSON.stringify({ timestamp: req.body?.timestamp })]
    );

    // Count consecutive declines since last answered call
    if (eventType === 'DECLINED') {
      const recent = await db.query(
        `SELECT event_type FROM device_history
         WHERE device_id = $1
           AND event_type IN ('CALL_DECLINED', 'CALL_ANSWERED')
         ORDER BY created_at DESC
         LIMIT 10`,
        [req.deviceAuth.sub]
      );
      let consecutiveDeclines = 0;
      for (const row of recent.rows) {
        if (row.event_type === 'CALL_ANSWERED') break;
        if (row.event_type === 'CALL_DECLINED') consecutiveDeclines++;
      }
      if (consecutiveDeclines >= 3) {
        const deviceRow = await db.query(
          `SELECT dealer_id, device_name, imei FROM devices WHERE id = $1`,
          [req.deviceAuth.sub]
        );
        const d = deviceRow.rows[0];
        if (d) {
          await db.query(
            `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, details)
             VALUES ($1, $2, 'FRAUD_SUSPECTED', 'system', $3)`,
            [req.deviceAuth.sub, callAssignmentId, JSON.stringify({ reason: 'call_decline_threshold', count: consecutiveDeclines })]
          );
          await db.query(
            `UPDATE devices SET status = 'fraud_suspected', updated_at = NOW() WHERE id = $1
             AND status NOT IN ('locked', 'decoupled', 'fraud_suspected')`,
            [req.deviceAuth.sub]
          );
          safeSse('pushToDealer', [d.dealer_id, 'fraud_suspected', {
            deviceId: req.deviceAuth.sub, deviceName: d.device_name,
            imei: d.imei, reason: 'call_decline_threshold'
          }]);
        }
      }
    }

    return res.json({ success: true });
  } catch (error) {
    logger.error('Call event failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to record call event' });
  }
});

module.exports = router;
