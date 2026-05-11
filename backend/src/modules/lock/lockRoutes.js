const express = require('express');
const router = express.Router();
const { body, param } = require('express-validator');
const rateLimit = require('express-rate-limit');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole, requirePermission } = require('../../middleware/rbac');
const { validateRequest } = require('../../middleware/validateRequest');
const lockController = require('./lockController');

const lockRequestLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: parseInt(process.env.LOCK_REQUEST_RATE_LIMIT_MAX || '1000', 10),
  message: { error: 'Too many lock requests, please try again later' },
});

const tokenLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  message: { error: 'Too many token requests, please try again later' },
});

router.post(
  '/request',
  authenticateToken,
  requireRole('dealer', 'admin'),
  lockRequestLimiter,
  body('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('reason').isIn(['EMI_OVERDUE', 'SUSPECTED_FRAUD', 'SUSPECTED_SALE', 'DEVICE_STOLEN', 'TERMS_VIOLATION'])
    .withMessage('Valid lock reason is required'),
  body('note').optional().isString().isLength({ max: 200 }).withMessage('Note must be 200 characters or less'),
  validateRequest,
  lockController.requestLock
);

router.post(
  '/command',
  authenticateToken,
  requireRole('admin'),
  body('deviceImei').matches(/^\d{15}$/).withMessage('IMEI must be exactly 15 digits'),
  body('actionType').isString().notEmpty().withMessage('actionType is required'),
  body('lockLevel').optional().isIn(['NONE', 'REMINDER_MODE', 'PARTIAL_LOCK', 'FULL_LOCK']),
  body('metadata').optional().isObject(),
  validateRequest,
  lockController.generateCommand
);

router.post(
  '/paut',
  authenticateToken,
  requireRole('admin', 'dealer'),
  tokenLimiter,
  body('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('imei').optional().matches(/^\d{15}$/).withMessage('IMEI must be exactly 15 digits'),
  body('lockLevel').optional().isIn(['NONE', 'REMINDER_MODE', 'PARTIAL_LOCK', 'FULL_LOCK']),
  validateRequest,
  lockController.issuePaut
);

router.post(
  '/padt',
  authenticateToken,
  requireRole('admin'),
  tokenLimiter,
  body('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('imei').optional().matches(/^\d{15}$/).withMessage('IMEI must be exactly 15 digits'),
  body('ownerId').optional().isUUID(),
  body('dealerId').optional().isUUID(),
  validateRequest,
  lockController.issuePadt
);

router.get(
  '/device/:id/status',
  authenticateToken,
  param('id').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  lockController.getDeviceLockStatus
);

router.get(
  '/requests',
  authenticateToken,
  requireRole('dealer', 'admin'),
  lockController.getDealerLockRequests
);

router.post(
  '/paut/verify',
  authenticateToken,
  body('token').isString().notEmpty().withMessage('Token is required'),
  validateRequest,
  lockController.verifyPaut
);

router.post(
  '/paut/verify-and-consume',
  authenticateToken,
  body('token').isString().notEmpty().withMessage('Token is required'),
  validateRequest,
  lockController.verifyAndConsumePaut
);

router.post(
  '/padt/verify',
  authenticateToken,
  body('token').isString().notEmpty().withMessage('Token is required'),
  validateRequest,
  lockController.verifyPadt
);

router.post(
  '/unlock',
  authenticateToken,
  requireRole('admin', 'dealer'),
  body('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  lockController.requestUnlock
);

router.post(
  '/paut/revoke',
  authenticateToken,
  requireRole('admin'),
  body('jti').isUUID().withMessage('Valid token JTI is required'),
  validateRequest,
  lockController.revokePaut
);

router.post(
  '/padt/revoke',
  authenticateToken,
  requireRole('admin'),
  body('jti').isUUID().withMessage('Valid token JTI is required'),
  validateRequest,
  lockController.revokePadt
);

module.exports = router;
