const express = require('express');
const { body } = require('express-validator');
const { authenticateToken, requireRole } = require('../../middleware/auth');
const { createEnrollment } = require('./enrollmentController');

const router = express.Router();

// POST /api/v1/dealer/enrollments
// Dealer submits customer + device info.
// Returns { enrollment_id, token } — token is shown to dealer, who types it into user app.
router.post(
  '/',
  authenticateToken,
  requireRole('dealer'),
  body('customer_name').isString().trim().isLength({ min: 2, max: 128 }),
  body('nid_hash').isString().trim().isLength({ min: 64, max: 64 }),
  body('phone_number').isString().trim().isLength({ min: 7, max: 20 }),
  body('brand').isString().trim().isLength({ min: 1, max: 64 }),
  body('model').isString().trim().isLength({ min: 1, max: 64 }),
  body('imei1').isString().trim().isLength({ min: 15, max: 15 }).isNumeric(),
  body('imei2').optional({ nullable: true }).isString().trim().isLength({ min: 15, max: 15 }).isNumeric(),
  createEnrollment
);

module.exports = router;
