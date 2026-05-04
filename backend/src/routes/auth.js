const express = require('express');
const { body } = require('express-validator');
const authController = require('../modules/auth');
const { authenticateToken } = require('../middleware/auth');
const { validateRequest } = require('../middleware/validateRequest');
const { loginLimiter, verify2FALimiter } = require('../modules/auth/rateLimit');

const router = express.Router();

const {
  login,
  verify2FA,
  setup2FA,
  confirm2FA,
  generateBackupCodesHandler,
  disable2FA,
  refreshTokenHandler,
  logoutHandler,
  register,
  getMe
} = authController;

const verify2FAValidationRules = [
  body('tempToken').notEmpty(),
  body('code').optional().isLength({ min: 6, max: 6 }).isNumeric(),
  body('backupCode').optional().isString(),
  validateRequest
];

const passwordValidationRules = [
  body('password')
    .isLength({ min: 8 }).withMessage('Password must be at least 8 characters')
    .matches(/[A-Z]/).withMessage('Password must contain at least one uppercase letter')
    .matches(/[a-z]/).withMessage('Password must contain at least one lowercase letter')
    .matches(/[0-9]/).withMessage('Password must contain at least one number')
    .matches(/[!@#$%^&*(),.?":{}|<>]/).withMessage('Password must contain at least one special character')
];

router.post(
  '/register',
  body('email').isEmail().normalizeEmail(),
  ...passwordValidationRules,
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('phone').notEmpty().withMessage('Phone is required'),
  validateRequest,
  register
);

router.post(
  '/login',
  loginLimiter,
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
  validateRequest,
  login
);

router.post(
  '/2fa/verify',
  verify2FALimiter,
  ...verify2FAValidationRules,
  verify2FA
);

router.post('/verify-2fa', verify2FALimiter, ...verify2FAValidationRules, verify2FA);
router.post('/refresh', refreshTokenHandler);
router.post('/logout', authenticateToken, logoutHandler);
router.post('/2fa/setup', authenticateToken, setup2FA);

router.post(
  '/2fa/confirm',
  authenticateToken,
  body('code').isLength({ min: 6, max: 6 }).isNumeric(),
  validateRequest,
  confirm2FA
);

router.post('/2fa/backup', authenticateToken, generateBackupCodesHandler);

router.post(
  '/2fa/disable',
  authenticateToken,
  body('password').notEmpty(),
  body('code').isLength({ min: 6, max: 6 }).isNumeric(),
  validateRequest,
  disable2FA
);

router.get('/me', authenticateToken, getMe);

module.exports = router;
module.exports.passwordValidationRules = passwordValidationRules;
