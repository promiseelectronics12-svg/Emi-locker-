const express = require('express');
const asyncHandler = require('express-async-handler');
const bcrypt = require('bcryptjs');
const { body } = require('express-validator');
const { rateLimit } = require('express-rate-limit');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { validateRequest } = require('../middleware/validateRequest');
const { buildErrorResponse } = require('../middleware/errorHandler');
const { invalidateAllUserSessions, BCRYPT_ROUNDS } = require('../modules/auth');

const router = express.Router();

const passwordChangeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 5,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  handler: (req, res) => res.status(429).json(
    buildErrorResponse(429, 'RATE_LIMITED', 'Too many password change attempts. Please try again later.')
  )
});

const newPasswordValidationRules = [
  body('newPassword')
    .isLength({ min: 8 }).withMessage('Password must be at least 8 characters')
    .matches(/[A-Z]/).withMessage('Password must contain at least one uppercase letter')
    .matches(/[a-z]/).withMessage('Password must contain at least one lowercase letter')
    .matches(/[0-9]/).withMessage('Password must contain at least one number')
    .matches(/[!@#$%^&*(),.?":{}|<>]/).withMessage('Password must contain at least one special character')
];

const getMyProfile = asyncHandler(async (req, res) => {
  const result = await db.query(
    'SELECT id, email, name, phone, nid, address, created_at FROM users WHERE id = $1',
    [req.user.id]
  );

  if (result.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'USER_NOT_FOUND', 'User not found'));
  }

  return res.json(result.rows[0]);
});

const updateProfile = asyncHandler(async (req, res) => {
  const { name, phone, address } = req.body;

  const result = await db.query(
    `UPDATE users
     SET name = $1, phone = $2, address = $3, updated_at = NOW()
     WHERE id = $4
     RETURNING id, email, name, phone, address`,
    [name, phone, address, req.user.id]
  );

  return res.json(result.rows[0]);
});

const changePassword = asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;

  if (!currentPassword || !newPassword) {
    return res.status(400).json(
      buildErrorResponse(400, 'PASSWORD_CHANGE_INPUT_REQUIRED', 'Current and new password required')
    );
  }

  const user = await db.query('SELECT password_hash FROM users WHERE id = $1', [req.user.id]);
  if (user.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'USER_NOT_FOUND', 'User not found'));
  }

  const validPassword = await bcrypt.compare(currentPassword, user.rows[0].password_hash);
  if (!validPassword) {
    return res.status(401).json(buildErrorResponse(401, 'INVALID_CREDENTIALS', 'Current password is incorrect'));
  }

  const hashedPassword = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  await db.query(
    'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
    [hashedPassword, req.user.id]
  );

  await invalidateAllUserSessions(req.user.id);

  return res.json({ message: 'Password changed successfully' });
});

router.get('/me', authenticateToken, getMyProfile);
router.patch('/me', authenticateToken, updateProfile);
router.post(
  '/change-password',
  authenticateToken,
  passwordChangeLimiter,
  body('currentPassword').notEmpty().withMessage('Current password is required'),
  body('newPassword').notEmpty().withMessage('New password is required'),
  ...newPasswordValidationRules,
  validateRequest,
  changePassword
);

module.exports = router;
