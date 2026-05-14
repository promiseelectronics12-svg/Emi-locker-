const express = require('express');

const router = express.Router();
const { body } = require('express-validator');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const { authenticateToken } = require('../../middleware/auth');
const { validateSignedDeviceCommand } = require('../../middleware/deviceAuth');
const { requireRole } = require('../../middleware/rbac');
const {
  enrollDevice,
  getDevice,
  applyPolicy,
  updateFcmToken,
  getDeviceStatus,
  lockDevice,
  unlockDevice,
  decoupleDevice,
  getDevicesByOwner,
  verifyHardwareBinding,
  validateRequest,
  imeiValidation,
  serialValidation,
  socIdValidation,
  enrollmentTokenValidation,
  deviceIdParam,
  fcmTokenValidation,
  reasonValidation,
  unlockCodeValidation
} = require('./deviceController');

const enrollRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 5,
  message: { error: 'Too many enrollment attempts, please try again after an hour' }
});

const lockUnlockRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 10,
  message: { error: 'Too many lock/unlock attempts, please try again after an hour' }
});

router.post(
  '/enroll',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  enrollRateLimiter,
  enrollmentTokenValidation,
  imeiValidation,
  serialValidation,
  socIdValidation,
  validateRequest,
  enrollDevice
);

// GET /devices — alias for /my, used by user app ApiService.getDevices()
router.get('/', authenticateToken, getDevicesByOwner);

router.get('/my', authenticateToken, getDevicesByOwner);

router.get('/:id', authenticateToken, deviceIdParam, validateRequest, getDevice);

router.post(
  '/:id/policy',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  deviceIdParam,
  validateRequest,
  applyPolicy
);

router.post(
  '/:id/fcm-token',
  authenticateToken,
  deviceIdParam,
  fcmTokenValidation,
  validateRequest,
  updateFcmToken
);

router.get('/:id/status', authenticateToken, deviceIdParam, validateRequest, getDeviceStatus);

router.post(
  '/:id/lock',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  validateSignedDeviceCommand,
  lockUnlockRateLimiter,
  deviceIdParam,
  reasonValidation,
  unlockCodeValidation,
  validateRequest,
  lockDevice
);

router.post(
  '/:id/unlock',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  validateSignedDeviceCommand,
  lockUnlockRateLimiter,
  deviceIdParam,
  reasonValidation,
  unlockCodeValidation,
  validateRequest,
  unlockDevice
);

router.post(
  '/:id/decouple',
  authenticateToken,
  requireRole('admin', 'reseller'),
  validateSignedDeviceCommand,
  deviceIdParam,
  validateRequest,
  decoupleDevice
);

router.post(
  '/:id/verify-hardware',
  authenticateToken,
  deviceIdParam,
  body('imei')
    .matches(/^\d{15}$/)
    .withMessage('IMEI must be 15 digits'),
  body('serialNumber').isString().isLength({ min: 1, max: 64 }),
  body('socId').isString().isLength({ min: 1, max: 128 }),
  validateRequest,
  verifyHardwareBinding
);

// Device-token authenticated endpoints (no user session required)

const db = require('../../config/database');
const logger = require('../../utils/logger');

async function requireDeviceToken(req, res, next) {
  const token = req.headers['x-device-token'];
  const timestamp = req.headers['x-device-timestamp'];
  const nonce = req.headers['x-device-nonce'];
  const deviceId = req.params.id;

  if (!token || !timestamp || !nonce) {
    return res.status(401).json({ success: false, error: 'Device token required' });
  }
  if (Date.now() - parseInt(timestamp, 10) > 300000) {
    return res.status(401).json({ success: false, error: 'Device token expired' });
  }

  try {
    const result = await db.query(`SELECT id FROM devices WHERE id = $1`, [deviceId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Device not found' });
    }

    const secret = process.env.DEVICE_SIGNING_SECRET || 'dev-device-signing-secret';
    const expected = crypto
      .createHmac('sha256', secret)
      .update(`${deviceId}${timestamp}${nonce}`)
      .digest('hex');

    if (!crypto.timingSafeEqual(Buffer.from(token, 'hex'), Buffer.from(expected, 'hex'))) {
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    req.deviceId = deviceId;
    next();
  } catch (err) {
    logger.error('Device token auth error', err);
    return res.status(500).json({ success: false, error: 'Authentication error' });
  }
}

// POST /devices/:id/sim-event — SIM swap detected on device
router.post('/:id/sim-event', requireDeviceToken, async (req, res) => {
  try {
    const { event_type, old_sim_hash, new_sim_hash, lat, lon } = req.body;
    const { deviceId } = req;

    const validTypes = ['SIM_CHANGED', 'SIM_REMOVED', 'SIM_RESTORED'];
    if (!validTypes.includes(event_type)) {
      return res.status(400).json({ success: false, error: 'Invalid event_type' });
    }

    await db.query(
      `INSERT INTO sim_events (device_id, event_type, old_sim_hash, new_sim_hash, location_lat, location_lon)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [deviceId, event_type, old_sim_hash || null, new_sim_hash || null, lat || null, lon || null]
    );

    if (event_type === 'SIM_CHANGED') {
      const fraudService = require('../fraud/fraudService');
      await fraudService.handleSimChangeEvent({ deviceId, lat, lon });
    }

    res.json({ success: true, received: true });
  } catch (err) {
    logger.error('SIM event error', err);
    res.status(500).json({ success: false, error: 'Failed to record SIM event' });
  }
});

// POST /devices/:id/theft-capture — silent witness capture (fake shutdown / FRP / wrong codes)
router.post('/:id/theft-capture', requireDeviceToken, async (req, res) => {
  try {
    const { trigger, lat, lon, has_photo, has_audio, evidence_ref } = req.body;
    const { deviceId } = req;

    const validTriggers = ['FAKE_SHUTDOWN', 'FRP_ATTEMPT', 'WRONG_CODE_5X'];
    if (!validTriggers.includes(trigger)) {
      return res.status(400).json({ success: false, error: 'Invalid trigger' });
    }

    await db.query(
      `INSERT INTO theft_captures (device_id, trigger, has_photo, has_audio, location_lat, location_lon, evidence_ref)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        deviceId,
        trigger,
        has_photo || false,
        has_audio || false,
        lat || null,
        lon || null,
        evidence_ref || null
      ]
    );

    const fraudService = require('../fraud/fraudService');

    await fraudService.createSecurityEvent({
      deviceId,
      eventType: 'INTEGRITY_FAILURE',
      severity: 'CRITICAL',
      details: { trigger, has_photo, has_audio, lat, lon, source: 'theft_capture' }
    });

    await fraudService.alertDealer(
      deviceId,
      `THEFT ALERT: ${trigger} detected on device. ${has_photo ? 'Photo captured.' : ''} ${has_audio ? 'Audio captured.' : ''}`
    );

    res.json({ success: true, received: true });
  } catch (err) {
    logger.error('Theft capture error', err);
    res.status(500).json({ success: false, error: 'Failed to record theft capture' });
  }
});

module.exports = router;
