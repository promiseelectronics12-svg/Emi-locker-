const { validationResult } = require('express-validator');
const logger = require('../../utils/logger');
const db = require('../../config/database');
const { verifyStagingActivation } = require('./deviceActivationService');

async function verifyActivation(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Invalid activation request', details: errors.array() });
  }

  try {
    const result = await verifyStagingActivation(req.body);
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    if (statusCode >= 500) {
      logger.error('Device activation verification failed:', error);
    }

    return res.status(statusCode).json({
      success: false,
      error: statusCode >= 500 ? 'Activation verification failed' : error.message
    });
  }
}

async function preRegisterDevice(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Invalid request', details: errors.array() });
  }

  const { imei, fcm_token, brand, model, android_id } = req.body;

  try {
    // Upsert: create or update device record by IMEI with FCM token.
    // Status is 'pending' until dealer completes enrollment.
    await db.query(
      `INSERT INTO devices (imei, fcm_token, brand, model, android_id, status,
                            fcm_token_status, last_seen_at, device_health_status,
                            created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'pending', 'valid', NOW(), 'online', NOW(), NOW())
       ON CONFLICT (imei) DO UPDATE
         SET fcm_token  = EXCLUDED.fcm_token,
             fcm_token_status = 'valid',
             last_seen_at = NOW(),
             device_health_status = 'online',
             app_uninstall_suspected_at = NULL,
             updated_at = NOW()
             ${brand    ? ", brand = EXCLUDED.brand"     : ""}
             ${model    ? ", model = EXCLUDED.model"     : ""}
             ${android_id ? ", android_id = EXCLUDED.android_id" : ""}
       WHERE devices.status IN ('pending', 'enrolled')`,
      [imei, fcm_token, brand || null, model || null, android_id || null]
    );

    logger.info('Device pre-registered', { imei: imei.slice(-4) });
    return res.status(200).json({ success: true });
  } catch (err) {
    logger.error('Device pre-registration failed', { error: err.message });
    return res.status(500).json({ error: 'Pre-registration failed' });
  }
}

async function confirmBinding(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Invalid request', details: errors.array() });
  }

  const { confirmFromDevice } = require('../enrollment/enrollmentService');
  try {
    const result = await confirmFromDevice({ code: req.body.code, imei: req.body.imei });
    return res.status(200).json(result);
  } catch (err) {
    const status = err.statusCode || 500;
    if (status >= 500) logger.error('confirmBinding failed', { error: err.message });
    return res.status(status).json({ error: err.message || 'Binding confirmation failed' });
  }
}

async function reportDeviceEvent(req, res) {
  const { deviceId } = req.params;
  const { type, lat, lng, timestamp } = req.body;

  if (!deviceId || !type) return res.status(400).json({ error: 'deviceId and type required' });

  const allowed = ['shutdown_detected', 'boot_after_shutdown'];
  if (!allowed.includes(type)) return res.status(400).json({ error: 'Unknown event type' });

  try {
    await db.query(
      `INSERT INTO device_events (device_id, type, lat, lng, recorded_at, created_at)
       VALUES ($1, $2, $3, $4, to_timestamp($5::bigint / 1000.0), NOW())
       ON CONFLICT DO NOTHING`,
      [
        deviceId,
        type,
        lat ? parseFloat(lat) : null,
        lng ? parseFloat(lng) : null,
        timestamp || Date.now().toString()
      ]
    );
    logger.info(`Device event: ${type} deviceId=${deviceId} lat=${lat} lng=${lng}`);
    return res.json({ success: true });
  } catch (err) {
    logger.error('reportDeviceEvent failed:', err);
    return res.status(500).json({ error: 'Failed to record event' });
  }
}

module.exports = {
  verifyActivation,
  preRegisterDevice,
  confirmBinding,
  reportDeviceEvent
};
