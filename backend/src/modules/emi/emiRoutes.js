const express = require('express');
const { body, param } = require('express-validator');
const emiController = require('./emiController');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');

const router = express.Router();

router.post(
  '/schedule',
  authenticateToken,
  [
    body('deviceId').isUUID().withMessage('Valid device ID is required'),
    body('totalAmount').isFloat({ min: 0.01 }).withMessage('Total amount must be positive'),
    body('downPayment').isFloat({ min: 0 }).withMessage('Down payment must be non-negative'),
    body('emiAmount').isFloat({ min: 0.01 }).withMessage('EMI amount must be positive'),
    body('duration').isInt({ min: 1, max: 60 }).withMessage('Duration must be 1-60 months'),
    body('startDate').isISO8601().withMessage('Valid start date is required'),
    body('graceDays').optional().isInt({ min: 0, max: 30 }).withMessage('Grace days must be 0-30'),
    body('dealerId').isUUID().withMessage('Valid dealer ID is required')
  ],
  emiController.validateRequest,
  emiController.createSchedule
);

router.get(
  '/:deviceId',
  authenticateToken,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  emiController.validateRequest,
  emiController.getSchedule
);

router.post(
  '/:deviceId/payment',
  authenticateToken,
  [
    param('deviceId').isUUID().withMessage('Valid device ID is required'),
    body('amount').isFloat({ min: 0.01 }).withMessage('Payment amount must be positive'),
    body('method').isIn(['cash', 'bank_transfer', 'bKash', 'nagad', 'rocket', 'card', 'other'])
      .withMessage('Valid payment method is required'),
    body('txId').optional().isString().isLength({ max: 255 }),
    body('installmentNumber').optional().isInt({ min: 1 }),
    body('note').optional().isString().isLength({ max: 500 })
  ],
  emiController.validateRequest,
  emiController.recordPayment
);

router.get(
  '/:deviceId/overdue-status',
  authenticateToken,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  emiController.validateRequest,
  emiController.getOverdueStatus
);

router.post(
  '/:deviceId/grace-period',
  authenticateToken,
  [
    param('deviceId').isUUID().withMessage('Valid device ID is required'),
    body('reason').optional().isString().isLength({ max: 500 })
  ],
  emiController.validateRequest,
  emiController.requestGracePeriod
);

router.get(
  '/upcoming',
  authenticateToken,
  emiController.getUpcoming
);

router.get(
  '/:deviceId/decoupling-status',
  authenticateToken,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  emiController.validateRequest,
  emiController.getDecouplingStatus
);

router.post(
  '/:deviceId/flag-fraud',
  authenticateToken,
  requireRole('dealer', 'admin'),
  [
    param('deviceId').isUUID().withMessage('Valid device ID is required'),
    body('reason').optional().isString().isLength({ max: 500 })
  ],
  emiController.validateRequest,
  emiController.flagFraud
);

router.post(
  '/:deviceId/execute-decoupling',
  authenticateToken,
  requireRole('admin'),
  [
    param('deviceId').isUUID().withMessage('Valid device ID is required'),
    body('rtocCode').isString().notEmpty().withMessage('RTOC code is required')
  ],
  emiController.validateRequest,
  emiController.executeDecoupling
);

router.get(
  '/:deviceId/lock-status',
  authenticateToken,
  param('deviceId').isUUID().withMessage('Valid device ID is required'),
  emiController.validateRequest,
  emiController.getLockStatus
);

module.exports = router;