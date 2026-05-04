const bcrypt = require('bcryptjs');
const QRCode = require('qrcode');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');
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

function errorResponse(res, status, code, message, extra = {}) {
  return res.status(status).json({
    status: 'error',
    code,
    message,
    ...extra
  });
}

async function login(req, res) {
  const { email, password } = req.body;
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
  const refreshIds = await redis.smembers(`user_refresh_tokens:${userId}`);

  for (const sessionId of sessionIds) {
    await redis.del(`session:${sessionId}`);
  }

  for (const refreshId of refreshIds) {
    await redis.del(`refresh:${refreshId}`);
  }

  await redis.del(`user_sessions:${userId}`);
  await redis.del(`user_refresh_tokens:${userId}`);
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
    name: user.name,
    role: user.role,
    status: user.status
  };
}

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
  getMe,
  storeSession,
  validateSession,
  invalidateSession,
  invalidateAllUserSessions,
  ROLES,
  BCRYPT_ROUNDS
};
