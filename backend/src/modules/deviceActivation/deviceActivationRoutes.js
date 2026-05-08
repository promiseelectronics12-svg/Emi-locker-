const express = require('express');
const rateLimit = require('express-rate-limit');
const { body } = require('express-validator');
const { verifyActivation } = require('./deviceActivationController');

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

module.exports = router;
