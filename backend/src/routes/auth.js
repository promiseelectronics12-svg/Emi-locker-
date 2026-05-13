const express = require('express');
const bcrypt = require('bcryptjs');
const { body } = require('express-validator');
const adminService = require('../modules/admin/adminService');
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
  registerDealer,
  registerReseller,
  getMe,
  googleStatus,
  bindGoogle,
  googleLogin,
  forgotPassword,
  verifyPasswordResetOtp,
  resetPassword,
  verifyDeviceOtp,
  listTrustedDevices,
  removeTrustedDevice
} = authController;

const verify2FAValidationRules = [
  body('tempToken').notEmpty(),
  body('code').optional().isLength({ min: 6, max: 6 }).isNumeric(),
  body('backupCode').optional().isString(),
  validateRequest
];

const passwordValidationRules = [
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/[A-Z]/)
    .withMessage('Password must contain at least one uppercase letter')
    .matches(/[a-z]/)
    .withMessage('Password must contain at least one lowercase letter')
    .matches(/[0-9]/)
    .withMessage('Password must contain at least one number')
    .matches(/[!@#$%^&*(),.?":{}|<>]/)
    .withMessage('Password must contain at least one special character')
];

const newPasswordValidationRules = [
  body('newPassword')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters')
    .matches(/[A-Z]/)
    .withMessage('Password must contain at least one uppercase letter')
    .matches(/[a-z]/)
    .withMessage('Password must contain at least one lowercase letter')
    .matches(/[0-9]/)
    .withMessage('Password must contain at least one number')
    .matches(/[!@#$%^&*(),.?":{}|<>]/)
    .withMessage('Password must contain at least one special character')
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
  '/register/dealer',
  body('email').isEmail().normalizeEmail(),
  ...passwordValidationRules,
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('phone').notEmpty().withMessage('Phone is required'),
  validateRequest,
  registerDealer
);

router.post(
  '/register/reseller',
  body('email').isEmail().normalizeEmail(),
  ...passwordValidationRules,
  body('name').trim().notEmpty().withMessage('Name is required'),
  body('phone').notEmpty().withMessage('Phone is required'),
  validateRequest,
  registerReseller
);

router.post(
  '/login',
  loginLimiter,
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
  validateRequest,
  login
);

router.post('/2fa/verify', verify2FALimiter, ...verify2FAValidationRules, verify2FA);

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

// Google login and account recovery
router.get('/google/status', authenticateToken, googleStatus);

router.post(
  '/google/bind',
  authenticateToken,
  body('idToken').isString().notEmpty(),
  validateRequest,
  bindGoogle
);

router.post(
  '/google/login',
  body('idToken').isString().notEmpty(),
  body('device_fingerprint').optional().isString(),
  body('device_name').optional().isString(),
  validateRequest,
  googleLogin
);

router.post(
  '/forgot-password',
  body('email').isEmail().normalizeEmail(),
  validateRequest,
  forgotPassword
);

router.post(
  '/reset-password/verify',
  body('email').isEmail().normalizeEmail(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
  validateRequest,
  verifyPasswordResetOtp
);

router.post(
  '/reset-password',
  body('resetToken').isString().notEmpty(),
  ...newPasswordValidationRules,
  validateRequest,
  resetPassword
);

// Device-trust endpoints
router.post(
  '/verify-device-otp',
  body('email').isEmail().normalizeEmail(),
  body('device_fingerprint').notEmpty(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric(),
  validateRequest,
  verifyDeviceOtp
);

router.get('/trusted-devices', authenticateToken, listTrustedDevices);
router.delete('/trusted-devices/:deviceId', authenticateToken, removeTrustedDevice);

// ── Reseller invite (public — no auth required) ──────────────────────────
router.get('/reseller-invite/verify', body('token').optional(), async (req, res) => {
  const { token } = req.query;
  if (!token) return res.status(400).json({ error: 'Token required' });
  const invite = await adminService.verifyResellerInviteToken(token);
  if (!invite)
    return res.status(404).json({ success: false, error: 'Invalid or expired invite token' });
  res.json({ success: true, data: { email: invite.email, name: invite.name } });
});

router.post(
  '/reseller-invite/complete',
  body('token').isString().isLength({ min: 32 }),
  body('password').isString().isLength({ min: 8 }),
  validateRequest,
  async (req, res) => {
    const { token, password, photoUrl } = req.body;
    const passwordHash = await bcrypt.hash(password, 12);
    const result = await adminService.consumeResellerInviteToken(
      token,
      passwordHash,
      photoUrl || null
    );
    if (!result.success) return res.status(400).json({ success: false, error: result.error });
    res.json({ success: true, message: 'Reseller account created', data: result.reseller });
  }
);

module.exports = router;
module.exports.passwordValidationRules = passwordValidationRules;
