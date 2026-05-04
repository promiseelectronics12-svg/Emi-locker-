const express = require('express');
const { body, param } = require('express-validator');
const rateLimit = require('express-rate-limit');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');
const { validateRequest } = require('../../middleware/validateRequest');
const { authenticateDevice } = require('../../middleware/deviceAuth');
const decouplingController = require('./decouplingController');

const router = express.Router();

// ============================================================
// Rate limiters — prevent abuse
// ============================================================
const fraudFlagLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: { error: 'Too many fraud flag attempts, please try again later' },
});

const executeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5,
  message: { error: 'Too many decoupling execution attempts, please try again later' },
});

// ============================================================
// ADMIN ROUTES
// ============================================================

// GET /api/v1/decoupling/stats — decoupling statistics
router.get(
  '/stats',
  authenticateToken,
  requireRole('admin'),
  decouplingController.getStats
);

// POST /api/v1/decoupling/initiate — start decoupling for a device
router.post(
  '/initiate',
  authenticateToken,
  requireRole('admin'),
  body('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('emiScheduleId').optional().isUUID().withMessage('Valid EMI schedule ID required'),
  validateRequest,
  decouplingController.initiateDecoupling
);

// POST /api/v1/decoupling/:deviceId/final-payment — record final payment
router.post(
  '/:deviceId/final-payment',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('paymentId').isString().notEmpty().withMessage('paymentId is required'),
  body('amount').isFloat({ min: 0.01 }).withMessage('Valid amount is required'),
  validateRequest,
  decouplingController.handleFinalPayment
);

// POST /api/v1/decoupling/:deviceId/notify-dealer — trigger dealer notification + 5-day window
router.post(
  '/:deviceId/notify-dealer',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.notifyDealer
);

// POST /api/v1/decoupling/:deviceId/confirm-fraud — admin confirms fraud
router.post(
  '/:deviceId/confirm-fraud',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.confirmFraud
);

// POST /api/v1/decoupling/:deviceId/reject-fraud — admin rejects fraud, decoupling proceeds
router.post(
  '/:deviceId/reject-fraud',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.rejectFraud
);

// POST /api/v1/decoupling/:deviceId/execute — ADMIN ONLY, requires 2FA
router.post(
  '/:deviceId/execute',
  authenticateToken,
  requireRole('admin'),
  executeLimiter,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('totpCode')
    .isString()
    .isLength({ min: 6, max: 6 })
    .isNumeric()
    .withMessage('Valid 6-digit 2FA code is required'),
  validateRequest,
  decouplingController.executeDecoupling
);

// ============================================================
// DEALER / ADMIN ROUTES
// ============================================================

// GET /api/v1/decoupling/:deviceId/status — view decoupling status
router.get(
  '/:deviceId/status',
  authenticateToken,
  requireRole('admin', 'dealer'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.getStatus
);

// POST /api/v1/decoupling/:deviceId/fraud-flag — dealer flags fraud with evidence
// Dealer CAN: flag with written evidence
// Dealer CANNOT: block or delay decoupling
router.post(
  '/:deviceId/fraud-flag',
  authenticateToken,
  requireRole('dealer', 'admin'),
  fraudFlagLimiter,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  body('reason')
    .isString()
    .isLength({ min: 10, max: 2000 })
    .withMessage('Fraud reason is required (10-2000 characters)'),
  body('evidenceUrl').optional().isURL().withMessage('Evidence must be a valid URL'),
  validateRequest,
  decouplingController.flagFraud
);

// ============================================================
// ADMIN ONLY — audit and PADT
// ============================================================

// GET /api/v1/decoupling/:deviceId/audit — immutable audit trail
router.get(
  '/:deviceId/audit',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.getAuditTrail
);

// GET /api/v1/decoupling/:deviceId/padt-check — device checks for pending PADT on reconnect
// ADMIN ONLY — prevents leaking decoupling state, RTOC hash prefixes, and PADT expiry timestamps
router.get(
  '/:deviceId/padt-check',
  authenticateToken,
  requireRole('admin'),
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.checkPADT
);

// GET /api/v1/decoupling/:deviceId/padt-check — device-authenticated version for device reconnect
router.get(
  '/:deviceId/padt-check/device',
  authenticateDevice,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  validateRequest,
  decouplingController.checkPADT
);

module.exports = router;
