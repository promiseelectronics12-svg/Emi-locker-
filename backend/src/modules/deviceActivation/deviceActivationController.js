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

  const { imei, fcm_token, brand, model, android_id, device_bound_id } = req.body;

  if (!imei && !android_id && !device_bound_id) {
    return res.status(400).json({
      error: 'Pre-registration requires IMEI, Android ID, or device bound ID'
    });
  }

  try {
    const existing = await db.query(
      `SELECT id
       FROM devices
       WHERE ($1::text IS NOT NULL AND imei = $1)
          OR ($2::text IS NOT NULL AND android_id = $2)
          OR ($3::text IS NOT NULL AND device_bound_id = $3)
       ORDER BY created_at DESC
       LIMIT 1`,
      [imei || null, android_id || null, device_bound_id || null]
    );

    if (existing.rows.length) {
      await db.query(
        `UPDATE devices
         SET imei = COALESCE($2, imei),
             fcm_token = $3,
             brand = COALESCE($4, brand),
             model = COALESCE($5, model),
             android_id = COALESCE($6, android_id),
             device_bound_id = COALESCE($7, device_bound_id),
             fcm_token_status = 'valid',
             last_seen_at = NOW(),
             device_health_status = 'online',
             app_uninstall_suspected_at = NULL,
             updated_at = NOW()
         WHERE id = $1`,
        [
          existing.rows[0].id,
          imei || null,
          fcm_token,
          brand || null,
          model || null,
          android_id || null,
          device_bound_id || null
        ]
      );
    } else {
      await db.query(
        `INSERT INTO devices (imei, fcm_token, brand, model, android_id, device_bound_id, status,
                              fcm_token_status, last_seen_at, device_health_status,
                              created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, 'pending', 'valid', NOW(), 'online', NOW(), NOW())`,
        [imei || null, fcm_token, brand || null, model || null, android_id || null, device_bound_id || null]
      );
    }

    logger.info('Device pre-registered', {
      imei: imei ? imei.slice(-4) : null,
      androidId: android_id ? android_id.slice(-4) : null
    });
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
    const result = await confirmFromDevice({
      code: req.body.code,
      imei: req.body.imei,
      androidId: req.body.android_id,
      deviceBoundId: req.body.device_bound_id,
      brand: req.body.brand,
      model: req.body.model
    });
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
