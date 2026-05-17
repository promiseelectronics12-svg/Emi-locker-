const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const QRCode = require('qrcode');
const { v4: uuidv4 } = require('uuid');
const { OAuth2Client } = require('google-auth-library');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const emailService = require('../notifications/emailService');
const {
  setup: setupTotpSecret,
  verify: verifyStoredTotp,
  verifyTOTP,
  generateBackupCodes,
  verifyBackupCode
} = require('./totp');
const {
  generateAccessToken,
  generateRefreshToken,
  verifyToken,
  blacklistToken,
  isBlacklisted,
  storeRefreshToken,
  validateStoredRefreshToken,
  invalidateRefreshToken,
  revokeTokensIssuedBefore
} = require('./jwt');

const ROLES = {
  ADMIN: 'admin',
  RESELLER: 'reseller',
  DEALER: 'dealer',
  CUSTOMER: 'customer'
};

const ACCOUNT_LOCK_WINDOW_SECONDS = 15 * 60;
const ACCOUNT_LOCK_THRESHOLD = 5;
const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;
const BCRYPT_ROUNDS = 12;
const OTP_TTL_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;
const PASSWORD_RESET_TOKEN_TTL_SECONDS = 10 * 60;
const OTP_TYPES = {
  DEVICE_LOGIN: 'DEVICE_LOGIN',
  PASSWORD_RESET: 'PASSWORD_RESET'
};

let authSchemaReadyPromise = null;
const googleClient = new OAuth2Client();

function errorResponse(res, status, code, message, extra = {}) {
  return res.status(status).json({
    status: 'error',
    code,
    message,
    ...extra
  });
}

function requestMeta(req) {
  return {
    ip: req.ip || req.headers['x-forwarded-for'] || null,
    userAgent: req.get('user-agent') || null
  };
}

function otpHash(otp) {
  const secret = process.env.AUTH_OTP_SECRET || process.env.JWT_SECRET || 'emi-locker-dev-otp-secret';
  return crypto.createHmac('sha256', secret).update(String(otp)).digest('hex');
}

function getGoogleClientIds() {
  return [
    process.env.GOOGLE_AUTH_CLIENT_IDS,
    process.env.GOOGLE_WEB_CLIENT_ID,
    process.env.GOOGLE_ANDROID_CLIENT_ID,
    process.env.GOOGLE_CLIENT_ID
  ]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim())
    .filter(Boolean);
}

async function ensureAuthSchema() {
  if (!authSchemaReadyPromise) {
    authSchemaReadyPromise = db.query(`
      CREATE EXTENSION IF NOT EXISTS pgcrypto;

      CREATE TABLE IF NOT EXISTS user_google_accounts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        google_sub TEXT NOT NULL UNIQUE,
        google_email TEXT NOT NULL,
        google_email_verified BOOLEAN DEFAULT FALSE,
        bound_at TIMESTAMP DEFAULT NOW(),
        last_used_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id)
      );

      CREATE INDEX IF NOT EXISTS idx_user_google_accounts_user_id ON user_google_accounts(user_id);
      CREATE INDEX IF NOT EXISTS idx_user_google_accounts_email ON user_google_accounts(google_email);

      CREATE TABLE IF NOT EXISTS trusted_devices (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        device_fingerprint TEXT NOT NULL,
        device_name TEXT,
        last_used_at TIMESTAMP DEFAULT NOW(),
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id, device_fingerprint)
      );

      CREATE INDEX IF NOT EXISTS idx_trusted_devices_user_id ON trusted_devices(user_id);

      CREATE TABLE IF NOT EXISTS auth_otp_challenges (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        email TEXT NOT NULL,
        type TEXT NOT NULL,
        otp_hash TEXT NOT NULL,
        device_fingerprint TEXT,
        device_name TEXT,
        ip_address TEXT,
        user_agent TEXT,
        attempts INTEGER DEFAULT 0,
        max_attempts INTEGER DEFAULT ${OTP_MAX_ATTEMPTS},
        expires_at TIMESTAMP NOT NULL,
        consumed_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_auth_otp_user_type ON auth_otp_challenges(user_id, type);
      CREATE INDEX IF NOT EXISTS idx_auth_otp_email_type ON auth_otp_challenges(email, type);
      CREATE INDEX IF NOT EXISTS idx_auth_otp_device ON auth_otp_challenges(device_fingerprint);
      CREATE INDEX IF NOT EXISTS idx_auth_otp_expires ON auth_otp_challenges(expires_at);
    `);
  }
  return authSchemaReadyPromise;
}

async function createOtpChallenge({
  userId,
  email,
  type,
  otp,
  deviceFingerprint = null,
  deviceName = null,
  meta = {}
}) {
  await ensureAuthSchema();
  await db.query(
    `UPDATE auth_otp_challenges
     SET consumed_at = NOW()
     WHERE email = $1
       AND type = $2
       AND consumed_at IS NULL`,
    [email, type]
  );
  await db.query(
    `INSERT INTO auth_otp_challenges (
       user_id, email, type, otp_hash, device_fingerprint, device_name,
       ip_address, user_agent, expires_at
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW() + INTERVAL '${OTP_TTL_MINUTES} minutes')`,
    [
      userId,
      email,
      type,
      otpHash(otp),
      deviceFingerprint,
      deviceName,
      meta.ip || null,
      meta.userAgent || null
    ]
  );
}

async function consumeOtpChallenge({ email, type, otp, deviceFingerprint = null }) {
  await ensureAuthSchema();
  const result = await db.query(
    `SELECT id, user_id, otp_hash, attempts, max_attempts, expires_at, device_name
     FROM auth_otp_challenges
     WHERE email = $1
       AND type = $2
       AND consumed_at IS NULL
       AND ($3::text IS NULL OR device_fingerprint = $3)
     ORDER BY created_at DESC
     LIMIT 1`,
    [email, type, deviceFingerprint]
  );

  if (result.rows.length === 0) {
    return { ok: false, code: 'OTP_EXPIRED', message: 'Verification code expired or not found. Please request a new code.' };
  }

  const challenge = result.rows[0];
  if (new Date(challenge.expires_at).getTime() < Date.now()) {
    await db.query('UPDATE auth_otp_challenges SET consumed_at = NOW() WHERE id = $1', [challenge.id]);
    return { ok: false, code: 'OTP_EXPIRED', message: 'Verification code expired. Please request a new code.' };
  }

  if (Number(challenge.attempts) >= Number(challenge.max_attempts)) {
    return { ok: false, code: 'TOO_MANY_ATTEMPTS', message: 'Too many verification attempts. Request a new code.' };
  }

  if (otpHash(otp) !== challenge.otp_hash) {
    await db.query('UPDATE auth_otp_challenges SET attempts = attempts + 1 WHERE id = $1', [challenge.id]);
    return { ok: false, code: 'INVALID_OTP', message: 'Invalid verification code' };
  }

  await db.query(
    'UPDATE auth_otp_challenges SET consumed_at = NOW(), attempts = attempts + 1 WHERE id = $1',
    [challenge.id]
  );

  return {
    ok: true,
    userId: challenge.user_id,
    deviceName: challenge.device_name
  };
}

async function verifyGoogleIdToken(idToken) {
  const audiences = getGoogleClientIds();
  if (audiences.length === 0) {
    const error = new Error('Google auth client IDs are not configured');
    error.code = 'GOOGLE_AUTH_NOT_CONFIGURED';
    throw error;
  }

  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: audiences
  });
  const payload = ticket.getPayload();
  if (!payload?.sub || !payload?.email) {
    const error = new Error('Google token is missing identity claims');
    error.code = 'INVALID_GOOGLE_TOKEN';
    throw error;
  }
  return {
    sub: payload.sub,
    email: payload.email.toLowerCase().trim(),
    emailVerified: payload.email_verified === true,
    name: payload.name || ''
  };
}

async function isTrustedDevice(userId, deviceFingerprint) {
  if (!deviceFingerprint) return false;
  await ensureAuthSchema();
  const trusted = await db.query(
    'SELECT id FROM trusted_devices WHERE user_id = $1 AND device_fingerprint = $2',
    [userId, deviceFingerprint]
  );
  if (trusted.rows.length === 0) return false;
  await db.query(
    'UPDATE trusted_devices SET last_used_at = NOW() WHERE user_id = $1 AND device_fingerprint = $2',
    [userId, deviceFingerprint]
  );
  return true;
}

async function trustDevice(userId, deviceFingerprint, deviceName) {
  await ensureAuthSchema();
  await db.query(
    `INSERT INTO trusted_devices (user_id, device_fingerprint, device_name)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, device_fingerprint)
     DO UPDATE SET device_name = EXCLUDED.device_name, last_used_at = NOW()`,
    [userId, deviceFingerprint, deviceName || 'Unknown device']
  );
}

async function issueTokensOrDeviceChallenge(res, req, user, deviceFingerprint, deviceName) {
  await ensureAuthSchema();
  if (deviceFingerprint && await isTrustedDevice(user.id, deviceFingerprint)) {
    return issueTokens(res, user);
  }

  const demoEmails = ['dealer@emi-locker.com', 'reseller@emi-locker.com'];
  const disableDemoTrustBypass = process.env.DISABLE_DEMO_DEVICE_TRUST_BYPASS === 'true';
  if (deviceFingerprint && !disableDemoTrustBypass && demoEmails.includes(user.email)) {
    await trustDevice(user.id, deviceFingerprint, deviceName || 'Demo Device');
    return issueTokens(res, user);
  }

  if (deviceFingerprint) {
    const otp = String(crypto.randomInt(100000, 999999));
    await createOtpChallenge({
      userId: user.id,
      email: user.email,
      type: OTP_TYPES.DEVICE_LOGIN,
      otp,
      deviceFingerprint,
      deviceName: deviceName || 'Unknown device',
      meta: requestMeta(req)
    });

    try {
      await emailService.sendDeviceOtp(user.email, otp);
    } catch (err) {
      logger.error(`Failed to send device OTP email to ${user.email}: ${err.message}`);
      return errorResponse(res, 500, 'EMAIL_SEND_FAILED', 'Failed to send verification email. Try again.');
    }

    logger.info(`Device OTP sent to ${user.email} for new device`);
    return res.json({ requiresDeviceVerification: true, email: user.email });
  }

  return issueTokens(res, user);
}

async function login(req, res) {
  await ensureAuthSchema();
  const { email, password, device_fingerprint, device_name } = req.body;
  const normalizedEmail = email.toLowerCase().trim();

  const result = await db.query(
    `SELECT id, email, password_hash, role, status, totp_secret, totp_enabled, name
     FROM users
     WHERE email = $1`,
    [normalizedEmail]
  );

  if (result.rows.length === 0) {
    logger.warn(`Failed login attempt for non-existent user: ${normalizedEmail}`);
    return errorResponse(res, 401, 'INVALID_CREDENTIALS', 'Invalid credentials');
  }

  const user = result.rows[0];
  const accountLock = await getAccountLockState(user.id);

  if (accountLock.locked) {
    return errorResponse(res, 423, 'ACCOUNT_LOCKED', 'Account is temporarily locked. Contact support or try again later.');
  }

  if (user.status === 'locked') {
    await db.query(
      'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2 AND status = $3',
      ['active', user.id, 'locked']
    );
    user.status = 'active';
  }

  if (user.status !== 'active') {
    return errorResponse(res, 401, 'ACCOUNT_INACTIVE', 'Account is not active');
  }

  const validPassword = await bcrypt.compare(password, user.password_hash);
  if (!validPassword) {
    const lockTriggered = await recordFailedLoginAttempt(user.id);
    logger.warn(`Failed login attempt for ${normalizedEmail}`);
    return errorResponse(
      res,
      lockTriggered ? 423 : 401,
      lockTriggered ? 'ACCOUNT_LOCKED' : 'INVALID_CREDENTIALS',
      lockTriggered
        ? 'Account locked due to repeated failed login attempts.'
        : 'Invalid credentials'
    );
  }

  await clearFailedLoginAttempts(user.id);

  if (device_fingerprint) {
    return issueTokensOrDeviceChallenge(res, req, user, device_fingerprint, device_name);
  }

  const tempToken = uuidv4();
  await storeTempToken(tempToken, user.id, 5 * 60, {
    requires2FA: Boolean(user.totp_enabled && user.totp_secret)
  });

  logger.info(`Primary authentication complete for ${normalizedEmail}`);

  return res.json({
    requires2FA: Boolean(user.totp_enabled && user.totp_secret),
    tempToken,
    user: sanitizeUser(user)
  });
}
async function verify2FA(req, res) {
  const { tempToken, code, backupCode } = req.body;

  if (!tempToken) {
    return errorResponse(res, 400, 'TEMP_TOKEN_REQUIRED', 'Temporary token required');
  }

  const tempData = await getTempToken(tempToken);
  if (!tempData) {
    return errorResponse(res, 401, 'TEMP_TOKEN_INVALID', 'Temporary token expired or invalid');
  }

  const result = await db.query(
    `SELECT id, email, role, status, totp_secret, totp_enabled, backup_codes, name
     FROM users
     WHERE id = $1`,
    [tempData.userId]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 401, 'USER_NOT_FOUND', 'User not found');
  }

  const user = result.rows[0];
  if (user.status !== 'active') {
    return errorResponse(res, 401, 'ACCOUNT_INACTIVE', 'Account is not active');
  }

  let verified = !tempData.requires2FA;

  if (tempData.requires2FA) {
    if (backupCode) {
      verified = await verifyBackupCode(user.id, backupCode);
    } else if (code) {
      verified = await verifyStoredTotp(user.id, code);
    } else {
      return errorResponse(res, 400, 'TWO_FACTOR_REQUIRED', 'Verification code or backup code required');
    }
  }

  if (!verified) {
    logger.warn(`Failed 2FA verification for ${user.email}`);
    return errorResponse(res, 401, 'INVALID_2FA_CODE', 'Invalid verification code');
  }

  await deleteTempToken(tempToken);

  const accessToken = generateAccessToken(user);
  const refreshToken = generateRefreshToken(user);

  await storeSession(user.id, refreshToken.jti);
  await storeRefreshToken(user.id, refreshToken.token);
  await db.query('UPDATE users SET last_login = NOW(), updated_at = NOW() WHERE id = $1', [user.id]);

  logger.info(`User logged in successfully: ${user.email}`);

  return res.json({
    accessToken: accessToken.token,
    refreshToken: refreshToken.token,
    user: sanitizeUser(user)
  });
}

async function setup2FA(req, res) {
  const userId = req.user.id;
  const result = await db.query(
    'SELECT id, email, role, status, totp_enabled FROM users WHERE id = $1',
    [userId]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 404, 'USER_NOT_FOUND', 'User not found');
  }

  const user = result.rows[0];
  if (user.totp_enabled) {
    return errorResponse(res, 400, 'TWO_FACTOR_ALREADY_ENABLED', '2FA is already enabled');
  }

  const { secret, otpauthUrl } = await setupTotpSecret(user.id, user.email, user.role);
  const qrCodeDataUrl = await QRCode.toDataURL(otpauthUrl);

  logger.info(`2FA setup initiated for user ${user.email}`);

  return res.json({
    secret,
    qrCodeDataUrl,
    otpauthUrl,
    message: 'Scan the QR code with your authenticator app, then verify with a code.'
  });
}

async function confirm2FA(req, res) {
  const { code } = req.body;
  const userId = req.user.id;

  if (!code) {
    return errorResponse(res, 400, 'TWO_FACTOR_CODE_REQUIRED', 'Verification code required');
  }

  const result = await db.query(
    'SELECT totp_secret, totp_pending FROM users WHERE id = $1',
    [userId]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 404, 'USER_NOT_FOUND', 'User not found');
  }

  const user = result.rows[0];
  if (!user.totp_pending || !user.totp_secret) {
    return errorResponse(res, 400, 'TWO_FACTOR_NOT_PENDING', '2FA setup not initiated');
  }

  if (!verifyTOTP(code, user.totp_secret)) {
    return errorResponse(res, 401, 'INVALID_2FA_CODE', 'Invalid verification code');
  }

  const backupCodes = await generateBackupCodes(userId);

  await db.query(
    `UPDATE users
     SET totp_enabled = $1, totp_pending = $2, backup_codes = $3, updated_at = NOW()
     WHERE id = $4`,
    [true, false, backupCodes.hashed, userId]
  );

  logger.info(`2FA enabled for user ${userId}`);

  return res.json({
    message: '2FA has been enabled successfully',
    backupCodes: backupCodes.plain
  });
}

async function generateBackupCodesHandler(req, res) {
  const userResult = await db.query(
    'SELECT totp_enabled FROM users WHERE id = $1',
    [req.user.id]
  );

  if (userResult.rows.length === 0) {
    return errorResponse(res, 404, 'USER_NOT_FOUND', 'User not found');
  }

  if (!userResult.rows[0].totp_enabled) {
    return errorResponse(res, 400, 'TWO_FACTOR_NOT_ENABLED', 'Enable 2FA before generating backup codes');
  }

  const backupCodes = await generateBackupCodes(req.user.id);

  return res.json({
    message: 'Backup codes regenerated successfully',
    backupCodes: backupCodes.plain
  });
}

async function disable2FA(req, res) {
  const { password, code } = req.body;
  const userId = req.user.id;

  if (!password || !code) {
    return errorResponse(res, 400, 'TWO_FACTOR_DISABLE_INPUT_REQUIRED', 'Password and verification code required');
  }

  const result = await db.query(
    'SELECT password_hash, totp_secret, totp_enabled FROM users WHERE id = $1',
    [userId]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 404, 'USER_NOT_FOUND', 'User not found');
  }

  const user = result.rows[0];
  if (!await bcrypt.compare(password, user.password_hash)) {
    return errorResponse(res, 401, 'INVALID_CREDENTIALS', 'Invalid password');
  }

  if (!user.totp_enabled) {
    return errorResponse(res, 400, 'TWO_FACTOR_NOT_ENABLED', '2FA is not enabled');
  }

  if (!verifyTOTP(code, user.totp_secret)) {
    return errorResponse(res, 401, 'INVALID_2FA_CODE', 'Invalid verification code');
  }

  await db.query(
    `UPDATE users
     SET totp_enabled = $1, totp_secret = $2, backup_codes = $3, totp_pending = $4, updated_at = NOW()
     WHERE id = $5`,
    [false, null, null, false, userId]
  );

  logger.info(`2FA disabled for user ${userId}`);

  return res.json({ message: '2FA has been disabled' });
}

async function refreshTokenHandler(req, res) {
  const { refreshToken } = req.body;

  if (!refreshToken) {
    return errorResponse(res, 400, 'REFRESH_TOKEN_REQUIRED', 'Refresh token required');
  }

  let validation;

  try {
    validation = await validateStoredRefreshToken(refreshToken);
  } catch (error) {
    if (error.code === 'TOKEN_EXPIRED') {
      return errorResponse(res, 401, 'TOKEN_EXPIRED', 'Refresh token expired');
    }

    return errorResponse(res, 401, 'INVALID_TOKEN', 'Invalid refresh token');
  }

  if (!validation.valid) {
    return errorResponse(res, 401, 'INVALID_SESSION', 'Session expired or invalid');
  }

  if (await isBlacklisted(refreshToken)) {
    return errorResponse(res, 401, 'TOKEN_REVOKED', 'Token has been revoked');
  }

  const { decoded } = validation;
  if (!await validateSession(decoded.jti, decoded.userId)) {
    return errorResponse(res, 401, 'INVALID_SESSION', 'Session expired or invalid');
  }

  const result = await db.query(
    'SELECT id, email, role, status, name FROM users WHERE id = $1',
    [decoded.userId]
  );

  if (result.rows.length === 0 || result.rows[0].status !== 'active') {
    return errorResponse(res, 401, 'ACCOUNT_INACTIVE', 'User not found or inactive');
  }

  const user = result.rows[0];
  const newAccessToken = generateAccessToken(user);
  const newRefreshToken = generateRefreshToken(user);

  await invalidateSession(decoded.jti);
  await invalidateRefreshToken(decoded.jti);
  await blacklistToken(refreshToken);
  await storeSession(user.id, newRefreshToken.jti);
  await storeRefreshToken(user.id, newRefreshToken.token);

  logger.info(`Tokens refreshed for user ${user.email}`);

  return res.json({
    accessToken: newAccessToken.token,
    refreshToken: newRefreshToken.token
  });
}

async function logoutHandler(req, res) {
  const authHeader = req.headers.authorization;
  const accessToken = authHeader && authHeader.startsWith('Bearer ')
    ? authHeader.slice(7)
    : null;
  const { refreshToken } = req.body;

  if (accessToken) {
    await blacklistToken(accessToken);
  }

  if (refreshToken) {
    await blacklistToken(refreshToken);

    try {
      const decodedRefresh = verifyToken(refreshToken, 'refresh');
      await invalidateSession(decodedRefresh.jti);
      await invalidateRefreshToken(refreshToken);
    } catch (error) {
      logger.warn(`Failed to invalidate refresh token on logout: ${error.message}`);
    }
  }

  if (req.user?.jti) {
    await invalidateSession(req.user.jti);
  }

  logger.info(`User logged out: ${req.user?.email || req.user?.id || 'unknown'}`);

  return res.json({ message: 'Logged out successfully' });
}

async function register(req, res) {
  const {
    email, password, name, phone
  } = req.body;

  const existingUser = await db.query(
    'SELECT id FROM users WHERE email = $1 OR phone = $2',
    [email.toLowerCase().trim(), phone.trim()]
  );

  if (existingUser.rows.length > 0) {
    return errorResponse(res, 409, 'CONFLICT', 'User already exists with this email or phone');
  }

  const hashedPassword = await bcrypt.hash(password, BCRYPT_ROUNDS);
  const result = await db.query(
    `INSERT INTO users (email, password_hash, name, phone, role, status, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, 'active', NOW(), NOW())
     RETURNING id, email, name, phone, role, status, created_at`,
    [email.toLowerCase().trim(), hashedPassword, name.trim(), phone.trim(), ROLES.CUSTOMER]
  );

  logger.info(`New user registered: ${email}`);

  return res.status(201).json(result.rows[0]);
}

async function registerRole(req, res, role) {
  const {
    email,
    password,
    name,
    phone,
    shopName,
    shop_name: shopNameLegacy,
    companyName,
    company_name: companyNameLegacy,
    tradeLicense,
    trade_license: tradeLicenseLegacy,
    address,
    resellerCode,
    reseller_code: resellerCodeLegacy
  } = req.body;

  const normalizedEmail = email.toLowerCase().trim();
  const normalizedPhone = phone.trim();

  // Invite role must match the registration endpoint role
  if (req.validatedInvite && req.validatedInvite.role !== role) {
    return errorResponse(res, 403, 'INVITE_ROLE_MISMATCH', 'Invite is not valid for this registration type.');
  }

  const existingUser = await db.query(
    'SELECT id FROM users WHERE email = $1 OR phone = $2',
    [normalizedEmail, normalizedPhone]
  );

  if (existingUser.rows.length > 0) {
    return errorResponse(res, 409, 'CONFLICT', 'User already exists with this email or phone');
  }

  const client = await db.getClient();
  await client.query('BEGIN');

  try {
    const hashedPassword = await bcrypt.hash(password, BCRYPT_ROUNDS);
    const userResult = await client.query(
      `INSERT INTO users (email, password_hash, name, phone, role, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'active', NOW(), NOW())
       RETURNING id, email, name, phone, role, status, created_at`,
      [normalizedEmail, hashedPassword, name.trim(), normalizedPhone, role]
    );

    const user = userResult.rows[0];

    if (role === ROLES.RESELLER) {
      await client.query(
        `INSERT INTO resellers (
          id, name, email, phone, company_name, trade_license, address, status, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', NOW(), NOW())`,
        [
          user.id,
          name.trim(),
          normalizedEmail,
          normalizedPhone,
          companyName || companyNameLegacy || null,
          tradeLicense || tradeLicenseLegacy || null,
          address || null
        ]
      );
    }

    if (role === ROLES.DEALER) {
      let resellerId = null;
      // Invite reseller_id takes precedence over user-supplied code
      const code = req.validatedInvite?.reseller_id || resellerCode || resellerCodeLegacy;
      if (code) {
        const resellerResult = await client.query(
          `SELECT id FROM resellers
           WHERE id::TEXT = $1 OR email = $1
           LIMIT 1`,
          [String(code)]
        );
        resellerId = resellerResult.rows[0]?.id || null;
      }

      await client.query(
        `INSERT INTO dealers (
          user_id, reseller_id, name, email, phone, address, business_name,
          shop_name, trade_license, role, status, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, 'dealer', 'active', NOW(), NOW())`,
        [
          user.id,
          resellerId,
          name.trim(),
          normalizedEmail,
          normalizedPhone,
          address || null,
          shopName || shopNameLegacy || null,
          tradeLicense || tradeLicenseLegacy || null
        ]
      );
    }

    // Consume invite token atomically — guard against duplicate registrations
    if (req.validatedInvite) {
      const consumed = await client.query(
        `UPDATE dealer_invites
         SET used_at = NOW(), used_by = $2
         WHERE id = $1 AND used_at IS NULL AND expires_at > NOW()
         RETURNING id`,
        [req.validatedInvite.id, user.id]
      );
      if (!consumed.rows.length) {
        throw Object.assign(new Error('Invite already used or expired.'), { statusCode: 403 });
      }
    }

    const accessToken = generateAccessToken(user);
    const refreshToken = generateRefreshToken(user);
    await storeSession(user.id, refreshToken.jti);
    await storeRefreshToken(user.id, refreshToken.token);

    await client.query('COMMIT');

    return res.status(201).json({
      accessToken: accessToken.token,
      refreshToken: refreshToken.token,
      user: sanitizeUser(user)
    });
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function registerDealer(req, res) {
  return registerRole(req, res, ROLES.DEALER);
}

async function registerReseller(req, res) {
  return registerRole(req, res, ROLES.RESELLER);
}

async function getMe(req, res) {
  const result = await db.query(
    `SELECT id, email, name, phone, role, status, created_at, updated_at, last_login
     FROM users
     WHERE id = $1`,
    [req.user.id]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 404, 'USER_NOT_FOUND', 'User not found');
  }

  return res.json(result.rows[0]);
}

async function storeSession(userId, tokenId) {
  const redis = require('../../config/redis');

  await redis.setex(`session:${tokenId}`, SESSION_TTL_SECONDS, JSON.stringify({ userId, createdAt: Date.now() }));
  await redis.sadd(`user_sessions:${userId}`, tokenId);
  await redis.expire(`user_sessions:${userId}`, SESSION_TTL_SECONDS);
}

async function validateSession(tokenId, userId) {
  const redis = require('../../config/redis');
  const session = await redis.get(`session:${tokenId}`);

  if (!session) {
    return false;
  }

  const data = JSON.parse(session);
  return data.userId === userId;
}

async function invalidateSession(tokenId) {
  const redis = require('../../config/redis');
  const session = await redis.get(`session:${tokenId}`);

  if (session) {
    const data = JSON.parse(session);
    await redis.srem(`user_sessions:${data.userId}`, tokenId);
  }

  await redis.del(`session:${tokenId}`);
}

async function invalidateAllUserSessions(userId) {
  const redis = require('../../config/redis');
  const sessionIds = await redis.smembers(`user_sessions:${userId}`);
  const refreshIds = await redis.smembers(`userRefreshTokens:${userId}`);

  await Promise.all(sessionIds.map((sessionId) => redis.del(`session:${sessionId}`)));
  await Promise.all(refreshIds.map((refreshId) => redis.del(`refresh:${refreshId}`)));

  await redis.del(`user_sessions:${userId}`);
  await redis.del(`userRefreshTokens:${userId}`);
  await revokeTokensIssuedBefore(userId);
}

async function storeTempToken(token, userId, ttlSeconds, extra = {}) {
  const redis = require('../../config/redis');
  await redis.setex(`temp_token:${token}`, ttlSeconds, JSON.stringify({ userId, ...extra }));
}

async function getTempToken(token) {
  const redis = require('../../config/redis');
  const data = await redis.get(`temp_token:${token}`);
  return data ? JSON.parse(data) : null;
}

async function deleteTempToken(token) {
  const redis = require('../../config/redis');
  await redis.del(`temp_token:${token}`);
}

async function getAccountLockState(userId) {
  const redis = require('../../config/redis');
  const attemptsKey = `failed_attempts:${userId}`;
  const lockKey = `account_lock:${userId}`;
  const [attempts, ttl, lockUntil] = await Promise.all([
    redis.get(attemptsKey),
    redis.ttl(attemptsKey),
    redis.get(lockKey)
  ]);

  return {
    attempts: attempts ? parseInt(attempts, 10) : 0,
    resetIn: ttl > 0 ? ttl : 0,
    locked: Boolean(lockUntil),
    lockUntil: lockUntil ? parseInt(lockUntil, 10) : null
  };
}

async function recordFailedLoginAttempt(userId) {
  const redis = require('../../config/redis');
  const attemptsKey = `failed_attempts:${userId}`;
  const lockKey = `account_lock:${userId}`;
  const attempts = await redis.incr(attemptsKey);

  if (attempts === 1) {
    await redis.expire(attemptsKey, ACCOUNT_LOCK_WINDOW_SECONDS);
  }

  if (attempts >= ACCOUNT_LOCK_THRESHOLD) {
    const lockUntil = Date.now() + (ACCOUNT_LOCK_WINDOW_SECONDS * 1000);

    await redis.setex(lockKey, ACCOUNT_LOCK_WINDOW_SECONDS, String(lockUntil));
    await db.query(
      'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2 AND status = $3',
      ['locked', userId, 'active']
    );

    return true;
  }

  return false;
}

async function clearFailedLoginAttempts(userId) {
  const redis = require('../../config/redis');
  await redis.del(`failed_attempts:${userId}`);
  await redis.del(`account_lock:${userId}`);
}

function sanitizeUser(user) {
  return {
    id: user.id,
    email: user.email,
    name: user.name || '',
    phone: user.phone || '',
    shop_name: user.shop_name || user.business_name || '',
    role: user.role,
    status: user.status,
    created_at: user.created_at || new Date().toISOString(),
    two_factor_enabled: Boolean(user.totp_enabled),
    is_active: user.status === 'active'
  };
}

// ── Device-trust helpers ──────────────────────────────────────────────────────

async function issueTokens(res, user) {
  const accessToken = generateAccessToken(user);
  const refreshToken = generateRefreshToken(user);
  await storeSession(user.id, refreshToken.jti);
  await storeRefreshToken(user.id, refreshToken.token);
  await db.query('UPDATE users SET last_login = NOW(), updated_at = NOW() WHERE id = $1', [user.id]);
  logger.info(`User logged in successfully: ${user.email}`);
  return res.json({
    accessToken: accessToken.token,
    refreshToken: refreshToken.token,
    user: sanitizeUser(user)
  });
}

async function googleStatus(req, res) {
  await ensureAuthSchema();
  const result = await db.query(
    `SELECT google_email, google_email_verified, bound_at, last_used_at
     FROM user_google_accounts
     WHERE user_id = $1`,
    [req.user.id]
  );
  const account = result.rows[0];
  return res.json({
    bound: Boolean(account),
    google_email: account?.google_email || null,
    google_email_verified: Boolean(account?.google_email_verified),
    bound_at: account?.bound_at || null,
    last_used_at: account?.last_used_at || null
  });
}

async function bindGoogle(req, res) {
  await ensureAuthSchema();
  const { idToken } = req.body;
  if (!idToken) {
    return errorResponse(res, 400, 'GOOGLE_TOKEN_REQUIRED', 'Google ID token is required');
  }

  let googleUser;
  try {
    googleUser = await verifyGoogleIdToken(idToken);
  } catch (error) {
    logger.warn(`Google bind failed for user ${req.user.id}: ${error.message}`);
    return errorResponse(
      res,
      error.code === 'GOOGLE_AUTH_NOT_CONFIGURED' ? 503 : 401,
      error.code || 'INVALID_GOOGLE_TOKEN',
      error.code === 'GOOGLE_AUTH_NOT_CONFIGURED'
        ? 'Google sign-in is not configured yet.'
        : 'Google account could not be verified.'
    );
  }

  const owner = await db.query(
    'SELECT user_id FROM user_google_accounts WHERE google_sub = $1 AND user_id <> $2',
    [googleUser.sub, req.user.id]
  );
  if (owner.rows.length > 0) {
    return errorResponse(res, 409, 'GOOGLE_ACCOUNT_IN_USE', 'This Google account is already bound to another EMI Locker account');
  }

  await db.query(
    `INSERT INTO user_google_accounts (
       user_id, google_sub, google_email, google_email_verified, bound_at, last_used_at
     )
     VALUES ($1, $2, $3, $4, NOW(), NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET
       google_sub = EXCLUDED.google_sub,
       google_email = EXCLUDED.google_email,
       google_email_verified = EXCLUDED.google_email_verified,
       last_used_at = NOW(),
       updated_at = NOW()`,
    [req.user.id, googleUser.sub, googleUser.email, googleUser.emailVerified]
  );

  logger.info(`Google account bound for user ${req.user.id}: ${googleUser.email}`);
  return res.json({
    bound: true,
    google_email: googleUser.email,
    google_email_verified: googleUser.emailVerified
  });
}

async function googleLogin(req, res) {
  await ensureAuthSchema();
  const { idToken, device_fingerprint, device_name } = req.body;
  if (!idToken) {
    return errorResponse(res, 400, 'GOOGLE_TOKEN_REQUIRED', 'Google ID token is required');
  }

  let googleUser;
  try {
    googleUser = await verifyGoogleIdToken(idToken);
  } catch (error) {
    logger.warn(`Google login failed: ${error.message}`);
    return errorResponse(
      res,
      error.code === 'GOOGLE_AUTH_NOT_CONFIGURED' ? 503 : 401,
      error.code || 'INVALID_GOOGLE_TOKEN',
      error.code === 'GOOGLE_AUTH_NOT_CONFIGURED'
        ? 'Google sign-in is not configured yet.'
        : 'Google account could not be verified.'
    );
  }

  const result = await db.query(
    `SELECT u.id, u.email, u.name, u.phone, u.role, u.status
     FROM user_google_accounts uga
     JOIN users u ON u.id = uga.user_id
     WHERE uga.google_sub = $1`,
    [googleUser.sub]
  );

  if (result.rows.length === 0) {
    return errorResponse(res, 401, 'GOOGLE_ACCOUNT_NOT_BOUND', 'This Google account is not linked to an EMI Locker account');
  }

  const user = result.rows[0];
  if (!['dealer', 'reseller', 'admin'].includes(user.role)) {
    return errorResponse(res, 403, 'ROLE_NOT_ALLOWED', 'Google login is not enabled for this account type');
  }
  if (user.status !== 'active') {
    return errorResponse(res, 401, 'ACCOUNT_INACTIVE', 'Account is not active');
  }

  await db.query(
    'UPDATE user_google_accounts SET last_used_at = NOW(), updated_at = NOW() WHERE google_sub = $1',
    [googleUser.sub]
  );

  return issueTokensOrDeviceChallenge(res, req, user, device_fingerprint, device_name);
}

async function forgotPassword(req, res) {
  await ensureAuthSchema();
  const normalizedEmail = String(req.body.email || '').toLowerCase().trim();
  const neutral = {
    message: 'If this account exists, we sent a password reset code.'
  };

  if (!normalizedEmail) return res.json(neutral);

  const result = await db.query(
    `SELECT id, email, role, status
     FROM users
     WHERE email = $1`,
    [normalizedEmail]
  );

  const user = result.rows[0];
  if (!user || !['dealer', 'reseller', 'admin'].includes(user.role) || user.status !== 'active') {
    logger.warn(`Password reset requested for unavailable account: ${normalizedEmail}`);
    return res.json(neutral);
  }

  const otp = String(crypto.randomInt(100000, 999999));
  await createOtpChallenge({
    userId: user.id,
    email: user.email,
    type: OTP_TYPES.PASSWORD_RESET,
    otp,
    meta: requestMeta(req)
  });

  try {
    await emailService.sendPasswordResetOtp(user.email, otp);
  } catch (error) {
    logger.error(`Failed to send password reset OTP to ${user.email}: ${error.message}`);
    return errorResponse(res, 500, 'EMAIL_SEND_FAILED', 'Failed to send reset email. Try again.');
  }

  logger.info(`Password reset OTP sent to ${user.email}`);
  return res.json(neutral);
}

async function verifyPasswordResetOtp(req, res) {
  const normalizedEmail = String(req.body.email || '').toLowerCase().trim();
  const otp = String(req.body.otp || '').trim();
  if (!normalizedEmail || !otp) {
    return errorResponse(res, 400, 'MISSING_FIELDS', 'email and otp are required');
  }

  const consumed = await consumeOtpChallenge({
    email: normalizedEmail,
    type: OTP_TYPES.PASSWORD_RESET,
    otp
  });
  if (!consumed.ok) {
    return errorResponse(res, consumed.code === 'TOO_MANY_ATTEMPTS' ? 429 : 401, consumed.code, consumed.message);
  }

  const resetToken = uuidv4();
  await storeTempToken(resetToken, consumed.userId, PASSWORD_RESET_TOKEN_TTL_SECONDS, {
    purpose: 'PASSWORD_RESET'
  });

  return res.json({ resetToken });
}

async function resetPassword(req, res) {
  const { resetToken, newPassword } = req.body;
  if (!resetToken || !newPassword) {
    return errorResponse(res, 400, 'MISSING_FIELDS', 'resetToken and newPassword are required');
  }

  const tokenData = await getTempToken(resetToken);
  if (!tokenData || tokenData.purpose !== 'PASSWORD_RESET') {
    return errorResponse(res, 401, 'RESET_TOKEN_INVALID', 'Password reset session expired. Request a new code.');
  }

  const hashedPassword = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);
  await db.query(
    'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
    [hashedPassword, tokenData.userId]
  );
  await deleteTempToken(resetToken);
  await invalidateAllUserSessions(tokenData.userId);
  logger.info(`Password reset completed for user ${tokenData.userId}`);
  return res.json({ message: 'Password reset successfully. Please log in again.' });
}

async function verifyDeviceOtp(req, res) {
  await ensureAuthSchema();
  const { email, device_fingerprint, otp } = req.body;
  if (!email || !device_fingerprint || !otp) {
    return errorResponse(res, 400, 'MISSING_FIELDS', 'email, device_fingerprint and otp are required');
  }

  const normalizedEmail = email.toLowerCase().trim();
  const userResult = await db.query(
    'SELECT id, email, role, status, name FROM users WHERE email = $1',
    [normalizedEmail]
  );
  if (userResult.rows.length === 0) {
    return errorResponse(res, 401, 'INVALID_CREDENTIALS', 'Invalid credentials');
  }
  const user = userResult.rows[0];
  if (user.status !== 'active') {
    return errorResponse(res, 401, 'ACCOUNT_INACTIVE', 'Account is not active');
  }

  const consumed = await consumeOtpChallenge({
    email: normalizedEmail,
    type: OTP_TYPES.DEVICE_LOGIN,
    otp,
    deviceFingerprint: device_fingerprint
  });

  if (!consumed.ok) {
    return errorResponse(
      res,
      consumed.code === 'TOO_MANY_ATTEMPTS' ? 429 : 401,
      consumed.code,
      consumed.message
    );
  }

  if (String(consumed.userId) !== String(user.id)) {
    logger.warn(`Device OTP user mismatch for ${normalizedEmail}`);
    return errorResponse(res, 401, 'INVALID_OTP', 'Invalid verification code');
  }

  await trustDevice(user.id, device_fingerprint, consumed.deviceName || 'Unknown device');

  logger.info(`New device trusted for user ${user.email}: ${consumed.deviceName || 'Unknown device'}`);
  return issueTokens(res, user);
}
async function listTrustedDevices(req, res) {
  const result = await db.query(
    `SELECT id, device_name, last_used_at, created_at
     FROM trusted_devices
     WHERE user_id = $1
     ORDER BY last_used_at DESC`,
    [req.user.id]
  );
  return res.json({ devices: result.rows });
}

async function removeTrustedDevice(req, res) {
  const { deviceId } = req.params;
  const result = await db.query(
    'DELETE FROM trusted_devices WHERE id = $1 AND user_id = $2 RETURNING id',
    [deviceId, req.user.id]
  );
  if (result.rows.length === 0) {
    return errorResponse(res, 404, 'NOT_FOUND', 'Device not found');
  }
  logger.info(`Trusted device removed for user ${req.user.id}: ${deviceId}`);
  return res.json({ message: 'Device removed' });
}

// ─────────────────────────────────────────────────────────────────────────────

module.exports = {
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
  removeTrustedDevice,
  storeSession,
  validateSession,
  invalidateSession,
  invalidateAllUserSessions,
  ROLES,
  BCRYPT_ROUNDS
};
