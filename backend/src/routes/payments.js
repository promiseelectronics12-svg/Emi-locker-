const express = require('express');
const asyncHandler = require('express-async-handler');
const { body } = require('express-validator');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const { validateRequest } = require('../middleware/validateRequest');
const { buildErrorResponse } = require('../middleware/errorHandler');

const router = express.Router();

const createPaymentValidation = [
  body('device_id').isUUID(),
  body('amount').isFloat({ min: 0.01 }).withMessage('Amount must be positive'),
  body('payment_method').isIn(['bkash', 'nagad', 'bank', 'cash']),
  validateRequest
];

const confirmPaymentValidation = [
  body('status').isIn(['confirmed', 'rejected']).withMessage('Status must be confirmed or rejected'),
  body('notes').optional().isString(),
  validateRequest
];

const getMyPayments = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT p.*, d.imei, d.model, d.brand
     FROM payments p
     JOIN devices d ON p.device_id = d.id
     WHERE p.user_id = $1
     ORDER BY p.created_at DESC`,
    [req.user.id]
  );

  return res.json(result.rows);
});

const createPayment = asyncHandler(async (req, res) => {
  const {
    device_id, amount, payment_method, transaction_id, notes
  } = req.body;

  const device = await db.query(
    'SELECT owner_id, monthly_amount, emi_remaining FROM devices WHERE id = $1',
    [device_id]
  );

  if (device.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));
  }

  if (device.rows[0].owner_id !== req.user.id) {
    return res.status(403).json(buildErrorResponse(403, 'ACCESS_DENIED', 'Access denied'));
  }

  const result = await db.query(
    `INSERT INTO payments (device_id, user_id, amount, payment_method, transaction_id, notes, status, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, 'pending', NOW())
     RETURNING *`,
    [device_id, req.user.id, amount, payment_method, transaction_id, notes]
  );

  return res.status(201).json(result.rows[0]);
});

const getPayment = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT p.*, d.imei, d.model, d.brand, u.name AS user_name, u.phone AS user_phone
     FROM payments p
     JOIN devices d ON p.device_id = d.id
     JOIN users u ON p.user_id = u.id
     WHERE p.id = $1
       AND (
         p.user_id = $2
         OR EXISTS(SELECT 1 FROM users WHERE id = $2 AND role = 'admin')
       )`,
    [req.params.id, req.user.id]
  );

  if (result.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'PAYMENT_NOT_FOUND', 'Payment not found'));
  }

  return res.json(result.rows[0]);
});

const confirmPayment = asyncHandler(async (req, res) => {
  const paymentAuthority = await db.query(
    `SELECT p.id, p.device_id, p.status, d.dealer_id, dl.user_id AS dealer_user_id
     FROM payments p
     JOIN devices d ON p.device_id = d.id
     LEFT JOIN dealers dl ON d.dealer_id = dl.id
     WHERE p.id = $1`,
    [req.params.id]
  );

  if (paymentAuthority.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'PAYMENT_NOT_FOUND', 'Payment not found'));
  }

  const payment = paymentAuthority.rows[0];
  const isAdmin = req.user.role === 'admin';
  const isAuthorizedDealer = req.user.role === 'dealer' && payment.dealer_user_id === req.user.id;

  if (!isAdmin && !isAuthorizedDealer) {
    return res.status(403).json(
      buildErrorResponse(403, 'INSUFFICIENT_PERMISSIONS', 'Insufficient permissions')
    );
  }

  const { status, notes } = req.body;
  const result = await db.query(
    `UPDATE payments
     SET status = $1, notes = COALESCE($2, notes), confirmed_at = NOW()
     WHERE id = $3
     RETURNING *`,
    [status, notes, req.params.id]
  );

  if (status === 'confirmed') {
    await db.query(
      `UPDATE devices
       SET emi_remaining = GREATEST(0, emi_remaining - 1), updated_at = NOW()
       WHERE id = $1`,
      [result.rows[0].device_id]
    );
  }

  return res.json(result.rows[0]);
});

router.get('/my', authenticateToken, getMyPayments);
router.post('/', authenticateToken, createPaymentValidation, createPayment);
router.get('/:id', authenticateToken, getPayment);
router.patch(
  '/:id/confirm',
  authenticateToken,
  requireRole('admin', 'dealer'),
  confirmPaymentValidation,
  confirmPayment
);

module.exports = router;
