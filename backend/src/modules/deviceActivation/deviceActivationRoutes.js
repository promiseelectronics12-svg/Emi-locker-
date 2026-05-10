const express = require('express');
const rateLimit = require('express-rate-limit');
const { body } = require('express-validator');
const { verifyActivation, preRegisterDevice, confirmBinding, reportDeviceEvent } = require('./deviceActivationController');

const router = express.Router();

const activationLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many activation attempts. Please try again later.' }
});

router.post(
  '/verify',
  activationLimiter,
  body('activationCode').isString().trim().isLength({ min: 6, max: 64 }),
  body('deviceBoundId').optional().isString().trim().isLength({ min: 4, max: 256 }),
  body('imei').optional().isString().trim().isLength({ min: 4, max: 64 }),
  body('androidId').optional().isString().trim().isLength({ min: 4, max: 128 }),
  body('serialNumber').optional().isString().trim().isLength({ max: 128 }),
  body('socId').optional().isString().trim().isLength({ max: 256 }),
  body('deviceName').optional().isString().trim().isLength({ max: 128 }),
  body('brand').optional().isString().trim().isLength({ max: 64 }),
  body('model').optional().isString().trim().isLength({ max: 64 }),
  body('sdk').optional().isInt({ min: 26, max: 100 }),
  body('fcmToken').optional().isString().trim().isLength({ max: 4096 }),
  verifyActivation
);

// Unauthenticated — device sends IMEI + FCM token before enrollment so dealer
// wizard can find the device by IMEI and deliver the 6-digit binding token.
router.post(
  '/pre-register',
  rateLimit({ windowMs: 60 * 60 * 1000, max: 10, message: { error: 'Too many pre-registration attempts' } }),
  body('imei').isString().trim().isLength({ min: 14, max: 16 }),
  body('fcm_token').isString().trim().isLength({ min: 10, max: 4096 }),
  body('brand').optional().isString().trim().isLength({ max: 64 }),
  body('model').optional().isString().trim().isLength({ max: 64 }),
  body('android_id').optional().isString().trim().isLength({ max: 128 }),
  preRegisterDevice
);

// Called by user app — dealer typed a 6-digit code into user app,
// user app reads real IMEI from hardware and sends both to server.
router.post(
  '/confirm',
  rateLimit({ windowMs: 15 * 60 * 1000, max: 10, message: { error: 'Too many attempts. Please wait.' } }),
  body('code').isString().trim().isLength({ min: 6, max: 6 }).isNumeric(),
  body('imei').optional().isString().trim().isLength({ min: 14, max: 16 }),
  confirmBinding
);

// Called by user app after binding — registers FCM token on the enrolled device record.
// No auth required: device just enrolled and has no credentials yet.
router.post(
  '/:deviceId/fcm',
  rateLimit({ windowMs: 60 * 60 * 1000, max: 20, message: { error: 'Rate limit exceeded' } }),
  body('fcm_token').isString().trim().isLength({ min: 10, max: 4096 }),
  async (req, res) => {
    const { validationResult } = require('express-validator');
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid request' });
    const db = require('../../config/database');
    try {
      await db.query(
        `UPDATE devices SET fcm_token = $1, updated_at = NOW() WHERE id = $2 AND status = 'enrolled'`,
        [req.body.fcm_token, req.params.deviceId]
      );
      return res.json({ success: true });
    } catch (e) {
      return res.status(500).json({ error: 'Failed to update FCM token' });
    }
  }
);

// Called by user app on startup if no device token stored.
// Authenticates via deviceId (stored) + imei (hardware read-only).
router.post(
  '/:deviceId/refresh-token',
  rateLimit({ windowMs: 60 * 60 * 1000, max: 10, message: { error: 'Rate limit exceeded' } }),
  body('imei').optional().isString().trim().isLength({ min: 14, max: 16 }),
  async (req, res) => {
    const { validationResult } = require('express-validator');
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid request' });

    const db = require('../../config/database');
    const jwt = require('jsonwebtoken');
    const { deviceId } = req.params;
    const { imei } = req.body;

    try {
      let result;
      if (imei) {
        const imeiHash = require('crypto').createHash('sha256').update(String(imei)).digest('hex');
        result = await db.query(
          `SELECT id, dealer_id, reseller_id FROM devices WHERE id = $1 AND imei_hash = $2 AND status = 'enrolled'`,
          [deviceId, imeiHash]
        );
      } else {
        result = await db.query(
          `SELECT id, dealer_id, reseller_id FROM devices WHERE id = $1 AND status = 'enrolled'`,
          [deviceId]
        );
      }

      if (!result.rows.length) {
        return res.status(404).json({ success: false, error: 'Device not found or not enrolled' });
      }

      const device = result.rows[0];
      const secret = process.env.DEVICE_TOKEN_SECRET || process.env.JWT_SECRET;
      if (!secret) return res.status(500).json({ error: 'Server misconfigured' });

      const deviceToken = jwt.sign(
        { sub: device.id, type: 'device', dealerId: device.dealer_id, resellerId: device.reseller_id },
        secret,
        { expiresIn: process.env.DEVICE_TOKEN_EXPIRES_IN || '30d' }
      );

      return res.json({ success: true, device_token: deviceToken });
    } catch (e) {
      return res.status(500).json({ error: 'Token refresh failed' });
    }
  }
);

// Device reports shutdown/boot events with GPS for theft detection
router.post(
  '/:deviceId/events',
  rateLimit({ windowMs: 60 * 1000, max: 5, message: { error: 'Rate limit exceeded' } }),
  body('type').isString().isIn(['shutdown_detected', 'boot_after_shutdown']),
  body('lat').optional().isFloat({ min: -90, max: 90 }),
  body('lng').optional().isFloat({ min: -180, max: 180 }),
  body('timestamp').optional().isString(),
  reportDeviceEvent
);

module.exports = router;
