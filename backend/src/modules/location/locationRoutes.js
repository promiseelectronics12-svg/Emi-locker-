const express = require('express');

const router = express.Router();
const { body, param, query } = require('express-validator');
const rateLimit = require('express-rate-limit');
const { param: paramValidator } = require('express-validator');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');
const { validateRequest } = require('../../middleware/validation');
const locationController = require('./locationController');

const locationDeviceIdParam = paramValidator('deviceId')
  .isUUID()
  .withMessage('Valid device ID required');
const validateLocationDeviceId = (req, res, next) => {
  const { validationResult } = require('express-validator');
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ errors: errors.array() });
  next();
};

async function validateDeviceToken(req, res, next) {
  const deviceToken = req.headers['x-device-token'];
  const { deviceId } = req.params;

  if (!deviceToken) {
    return res.status(401).json({ success: false, error: 'Device token required' });
  }

  try {
    const jwt = require('jsonwebtoken');
    const secret = process.env.DEVICE_TOKEN_SECRET;
    if (!secret) {
      logger.error('DEVICE_TOKEN_SECRET not configured');
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    let payload;
    try {
      payload = jwt.verify(deviceToken, secret, { algorithms: ['HS256'] });
    } catch (e) {
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    if (payload.type !== 'device' || payload.sub !== deviceId) {
      return res.status(401).json({ success: false, error: 'Token does not match device' });
    }

    const result = await db.query(`SELECT id FROM devices WHERE id = $1`, [deviceId]);
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Device not found' });
    }

    next();
  } catch (error) {
    logger.error('validateDeviceToken error:', error);
    return res.status(500).json({ success: false, error: 'Authentication error' });
  }
}

const reportRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { success: false, error: 'Too many location reports, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const pullRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  message: { success: false, error: 'Too many pull requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const historyRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  message: { success: false, error: 'Too many history requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const geofenceSetRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { success: false, error: 'Too many geofence set requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const geofenceGetRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  message: { success: false, error: 'Too many geofence get requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const geofenceDeleteRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { success: false, error: 'Too many geofence delete requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false
});

const pullLocationValidation = [
  body('reason').optional().isString().isLength({ min: 1, max: 255 }),
  validateRequest
];

function verifyDeviceOwnership(req, res, next) {
  const { deviceId } = req.params;
  const userId = req.user.id;
  const userRole = req.user.role;

  if (userRole === 'admin') {
    return next();
  }

  db.query(
    `SELECT d.id
     FROM devices d
     LEFT JOIN dealers dl ON dl.id = d.dealer_id
     LEFT JOIN dealers dl2 ON dl2.user_id = d.dealer_id
     LEFT JOIN resellers r ON r.id = d.reseller_id
     WHERE d.id = $1
       AND (dl.user_id = $2 OR dl2.user_id = $2 OR d.owner_id = $2 OR r.id = $2 OR d.dealer_id = $2)`,
    [deviceId, userId]
  )
    .then((result) => {
      if (result.rows.length === 0) {
        return res.status(403).json({ success: false, error: 'Access denied to this device' });
      }
      next();
    })
    .catch((error) => {
      logger.error('Device ownership verification error:', error);
      return res.status(500).json({ success: false, error: 'Verification error' });
    });
}

const reportLocationValidation = [
  body('latitude').isFloat({ min: -90, max: 90 }).withMessage('Valid latitude required'),
  body('longitude').isFloat({ min: -180, max: 180 }).withMessage('Valid longitude required'),
  body('accuracy').isFloat({ min: 0 }).withMessage('Accuracy must be positive'),
  body('timestamp').isISO8601().withMessage('Valid ISO timestamp required'),
  body('battery_level').optional().isInt({ min: 0, max: 100 }).withMessage('Battery level 0-100'),
  body('pull_id').optional().isString().isLength({ min: 1, max: 128 }),
  validateRequest
];

const setGeofenceValidation = [
  body('type').isIn(['circle', 'polygon']).withMessage('Geofence type must be circle or polygon'),
  body('name').isString().isLength({ min: 1, max: 100 }).withMessage('Geofence name required'),
  body('center_latitude').optional().isFloat({ min: -90, max: 90 }),
  body('center_longitude').optional().isFloat({ min: -180, max: 180 }),
  body('radius_meters').optional().isInt({ min: 100, max: 100000 }),
  body('coordinates').optional().isArray().withMessage('Coordinates must be array'),
  body('coordinates.*.latitude')
    .isFloat({ min: -90, max: 90 })
    .withMessage('Coordinate latitude must be between -90 and 90'),
  body('coordinates.*.longitude')
    .isFloat({ min: -180, max: 180 })
    .withMessage('Coordinate longitude must be between -180 and 180'),
  body('enabled').optional().isBoolean(),
  validateRequest
];

router.post(
  '/:deviceId/pull',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  pullRateLimiter,
  verifyDeviceOwnership,
  locationDeviceIdParam,
  validateLocationDeviceId,
  pullLocationValidation,
  locationController.pullLocation
);

router.post(
  '/:deviceId/report',
  reportRateLimiter,
  validateDeviceToken,
  locationDeviceIdParam,
  validateLocationDeviceId,
  reportLocationValidation,
  locationController.reportLocation
);

router.get(
  '/:deviceId/history',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  historyRateLimiter,
  verifyDeviceOwnership,
  locationDeviceIdParam,
  validateLocationDeviceId,
  locationController.getLocationHistory
);

router.post(
  '/:deviceId/geofence',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  geofenceSetRateLimiter,
  verifyDeviceOwnership,
  locationDeviceIdParam,
  validateLocationDeviceId,
  setGeofenceValidation,
  locationController.setGeofence
);

router.get(
  '/:deviceId/geofence',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  geofenceGetRateLimiter,
  verifyDeviceOwnership,
  locationDeviceIdParam,
  validateLocationDeviceId,
  locationController.getGeofence
);

router.delete(
  '/:deviceId/geofence',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  geofenceDeleteRateLimiter,
  verifyDeviceOwnership,
  locationDeviceIdParam,
  validateLocationDeviceId,
  locationController.deleteGeofence
);

// POST /location/:deviceId/anomaly — device reports a locally-detected anomaly
// Raw GPS history never reaches the server; only the anomaly signal is sent.
router.post(
  '/:deviceId/anomaly',
  reportRateLimiter,
  validateDeviceToken,
  locationDeviceIdParam,
  validateLocationDeviceId,
  body('alert_type')
    .isIn([
      'UNUSUAL_LOCATION',
      'IMPOSSIBLE_TRAVEL',
      'NEW_REGION',
      'RESET_WITH_RELOCATION',
      'SIM_CHANGE_RELOCATION',
      'EXTENDED_OFFLINE'
    ])
    .withMessage('Invalid alert_type'),
  body('area_description').optional().isString().isLength({ max: 255 }),
  body('confidence').optional().isInt({ min: 0, max: 100 }),
  body('lat').optional().isFloat({ min: -90, max: 90 }),
  body('lon').optional().isFloat({ min: -180, max: 180 }),
  validateRequest,
  async (req, res) => {
    try {
      const { deviceId } = req.params;
      const { alert_type, area_description, confidence, lat, lon } = req.body;

      await db.query(
        `INSERT INTO location_anomalies
           (device_id, alert_type, area_description, confidence, reveal_lat, reveal_lon)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          deviceId,
          alert_type,
          area_description || null,
          confidence || null,
          lat || null,
          lon || null
        ]
      );

      // Delegate two-signal correlation to fraud service
      const fraudService = require('../fraud/fraudService');
      await fraudService.handleLocationAnomalyEvent({ deviceId, alert_type, area_description });

      res.json({ success: true, received: true });
    } catch (err) {
      logger.error('Location anomaly report error', err);
      res.status(500).json({ success: false, error: 'Failed to record anomaly' });
    }
  }
);

module.exports = router;
