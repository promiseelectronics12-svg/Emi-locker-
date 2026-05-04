const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const rateLimit = require('express-rate-limit');
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

router.get(
  '/my',
  authenticateToken,
  getDevicesByOwner
);

router.get(
  '/:id',
  authenticateToken,
  deviceIdParam,
  validateRequest,
  getDevice
);

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

router.get(
  '/:id/status',
  authenticateToken,
  deviceIdParam,
  validateRequest,
  getDeviceStatus
);

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
  body('imei').matches(/^\d{15}$/).withMessage('IMEI must be 15 digits'),
  body('serialNumber').isString().isLength({ min: 1, max: 64 }),
  body('socId').isString().isLength({ min: 1, max: 128 }),
  validateRequest,
  verifyHardwareBinding
);

module.exports = router;
