const express = require('express');
const { body, param } = require('express-validator');
const { authenticateToken, requireRole } = require('../../middleware/auth');
const {
  createEnrollment,
  updateEnrollmentDeviceFallback,
  updateEnrollmentEmiTerms
} = require('./enrollmentController');

const router = express.Router();

function normalizeImei(value) {
  return String(value || '').replace(/\D/g, '');
}

function isValidImei(value) {
  const imei = normalizeImei(value);
  if (!/^\d{15}$/.test(imei)) return false;

  let sum = 0;
  for (let index = 0; index < imei.length; index += 1) {
    let digit = Number.parseInt(imei[index], 10);
    if (index % 2 === 1) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 === 0;
}

// POST /api/v1/dealer/enrollments
// Dealer submits customer info and requests a binding code.
// Returns { enrollment_id, token } — token is shown to dealer, who types it into user app.
router.post(
  '/',
  authenticateToken,
  requireRole('dealer'),
  body('customer_name').isString().trim().isLength({ min: 2, max: 128 }),
  body('nid_hash').isString().trim().isLength({ min: 64, max: 64 }),
  body('phone_number').isString().trim().isLength({ min: 7, max: 20 }),
  body('brand').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ min: 1, max: 64 }),
  body('model').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ min: 1, max: 64 }),
  body('imei1')
    .optional({ nullable: true, checkFalsy: true })
    .isString()
    .custom((value) => isValidImei(value))
    .withMessage('IMEI 1 must be a valid 15-digit IMEI.'),
  body('imei2')
    .optional({ nullable: true, checkFalsy: true })
    .isString()
    .custom((value, { req }) => {
      const imei2 = normalizeImei(value);
      if (!isValidImei(imei2)) return false;
      const imei1 = normalizeImei(req.body.imei1);
      return !imei1 || imei2 !== imei1;
    })
    .withMessage('IMEI 2 must be valid and different from IMEI 1.'),
  body('tier').optional().isIn(['standard', 'premium', 'vip']),
  body('totalAmount').optional({ nullable: true }).isFloat({ min: 0.01 }),
  body('downPayment').optional({ nullable: true }).isFloat({ min: 0 }),
  body('emiAmount').optional({ nullable: true }).isFloat({ min: 0.01 }),
  body('duration').optional({ nullable: true }).isInt({ min: 1, max: 60 }),
  body('startDate').optional({ nullable: true }).isISO8601(),
  body('graceDays').optional().isInt({ min: 0, max: 30 }),
  createEnrollment
);

router.patch(
  '/:enrollmentId/emi-terms',
  authenticateToken,
  requireRole('dealer'),
  param('enrollmentId').isUUID(),
  body('totalAmount').isFloat({ min: 0.01 }),
  body('downPayment').isFloat({ min: 0 }),
  body('emiAmount').isFloat({ min: 0.01 }),
  body('duration').isInt({ min: 1, max: 60 }),
  body('startDate').isISO8601(),
  body('graceDays').optional().isInt({ min: 0, max: 30 }),
  updateEnrollmentEmiTerms
);

router.patch(
  '/:enrollmentId/device-fallback',
  authenticateToken,
  requireRole('dealer'),
  param('enrollmentId').isUUID(),
  body('brand').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ min: 1, max: 64 }),
  body('model').optional({ nullable: true, checkFalsy: true }).isString().trim().isLength({ min: 1, max: 64 }),
  body('imei1')
    .optional({ nullable: true, checkFalsy: true })
    .isString()
    .custom((value) => isValidImei(value))
    .withMessage('IMEI 1 must be a valid 15-digit IMEI.'),
  body('imei2')
    .optional({ nullable: true, checkFalsy: true })
    .isString()
    .custom((value, { req }) => {
      const imei2 = normalizeImei(value);
      if (!isValidImei(imei2)) return false;
      const imei1 = normalizeImei(req.body.imei1);
      return !imei1 || imei2 !== imei1;
    })
    .withMessage('IMEI 2 must be valid and different from IMEI 1.'),
  updateEnrollmentDeviceFallback
);

module.exports = router;
