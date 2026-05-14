const crypto = require('crypto');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const logger = require('../../utils/logger');

const ACCESS_TOKEN_EXPIRY = '15m';
const REFRESH_TOKEN_EXPIRY = '7d';
const REFRESH_TOKEN_TTL_SECONDS = 7 * 24 * 60 * 60;

function normalizePem(value) {
  return value ? value.replace(/\\n/g, '\n') : null;
}

function readKeyFromFile(filename) {
  const fullPath = path.join(__dirname, '../../keys', filename);
  return fs.existsSync(fullPath) ? fs.readFileSync(fullPath, 'utf8') : null;
}

function loadSigningKeys() {
  const privateKey = normalizePem(process.env.JWT_PRIVATE_KEY) || readKeyFromFile('private.pem');
  const publicKey = normalizePem(process.env.JWT_PUBLIC_KEY) || readKeyFromFile('public.pem');

  if (!privateKey || !publicKey) {
    logger.error(
      'RS256 signing keys are required. Configure JWT_PRIVATE_KEY/JWT_PUBLIC_KEY or backend/keys/*.pem.'
    );
    process.exit(1);
  }

  return { privateKey, publicKey };
}

const { privateKey, publicKey } = loadSigningKeys();

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function buildPayload(user, type) {
  return {
    id: user.id,
    userId: user.id,
    email: user.email,
    role: user.role,
    type,
    jti: uuidv4()
  };
}

function generateAccessToken(user) {
  const payload = buildPayload(user, 'access');
  const token = jwt.sign(payload, privateKey, {
    algorithm: 'RS256',
    expiresIn: ACCESS_TOKEN_EXPIRY
  });

  return { token, jti: payload.jti };
}

function generateRefreshToken(user) {
  const payload = buildPayload(user, 'refresh');
  const token = jwt.sign(payload, privateKey, {
    algorithm: 'RS256',
    expiresIn: REFRESH_TOKEN_EXPIRY
  });

  return { token, jti: payload.jti };
}

function verifyToken(token, expectedType = null) {
  try {
    const decoded = jwt.verify(token, publicKey, { algorithms: ['RS256'] });

    if (expectedType && decoded.type !== expectedType) {
      const typeError = new Error('Invalid token type');
      typeError.code = 'INVALID_TOKEN_TYPE';
      throw typeError;
    }

    return decoded;
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      error.code = 'TOKEN_EXPIRED';
      throw error;
    }

    if (error.name === 'JsonWebTokenError' || error.name === 'NotBeforeError') {
      error.code = 'INVALID_TOKEN';
      throw error;
    }

    throw error;
  }
}

async function storeRefreshToken(userId, refreshToken) {
  const redis = require('../../config/redis');
  const decoded = verifyToken(refreshToken, 'refresh');
  const tokenHash = hashToken(refreshToken);

  await redis.setex(
    `refresh:${decoded.jti}`,
    REFRESH_TOKEN_TTL_SECONDS,
    JSON.stringify({ userId, tokenHash, issuedAt: decoded.iat || Math.floor(Date.now() / 1000) })
  );

  await redis.sadd(`userRefreshTokens:${userId}`, decoded.jti);
  await redis.expire(`userRefreshTokens:${userId}`, REFRESH_TOKEN_TTL_SECONDS);

  return decoded;
}

async function validateStoredRefreshToken(refreshToken, expectedUserId = null) {
  const redis = require('../../config/redis');
  const decoded = verifyToken(refreshToken, 'refresh');
  const stored = await redis.get(`refresh:${decoded.jti}`);

  if (!stored) {
    return { valid: false, decoded };
  }

  const session = JSON.parse(stored);
  const tokenHash = hashToken(refreshToken);

  if (session.tokenHash !== tokenHash) {
    return { valid: false, decoded };
  }

  if (expectedUserId && session.userId !== expectedUserId) {
    return { valid: false, decoded };
  }

  const revokedAfter = await getUserRevokedAfter(decoded.userId || decoded.id);
  if (revokedAfter && decoded.iat && decoded.iat <= revokedAfter) {
    return { valid: false, decoded };
  }

  return { valid: true, decoded, session };
}

async function invalidateRefreshToken(tokenOrJti) {
  const redis = require('../../config/redis');
  const jti = tokenOrJti.includes('.') ? verifyToken(tokenOrJti, 'refresh').jti : tokenOrJti;
  const session = await redis.get(`refresh:${jti}`);

  if (session) {
    const { userId } = JSON.parse(session);
    await redis.srem(`userRefreshTokens:${userId}`, jti);
  }

  await redis.del(`refresh:${jti}`);
}

async function blacklistToken(token) {
  const redis = require('../../config/redis');

  try {
    const decoded = jwt.decode(token);
    if (!decoded || !decoded.exp) return;

    const ttl = decoded.exp - Math.floor(Date.now() / 1000);
    if (ttl > 0) {
      await redis.setex(`blacklist:${token}`, ttl, '1');
    }
  } catch (error) {
    logger.error('Error blacklisting token:', error);
  }
}

async function isBlacklisted(token) {
  const redis = require('../../config/redis');
  const exists = await redis.exists(`blacklist:${token}`);
  return exists === 1;
}

async function revokeTokensIssuedBefore(userId, timestamp = Math.floor(Date.now() / 1000)) {
  const redis = require('../../config/redis');
  await redis.set(`user:revoked_after:${userId}`, String(timestamp));
}

async function getUserRevokedAfter(userId) {
  const redis = require('../../config/redis');
  const revokedAfter = await redis.get(`user:revoked_after:${userId}`);
  return revokedAfter ? parseInt(revokedAfter, 10) : null;
}

async function isUserTokenRevoked(decoded) {
  const revokedAfter = await getUserRevokedAfter(decoded.userId || decoded.id);
  return Boolean(revokedAfter && decoded.iat && decoded.iat <= revokedAfter);
}

module.exports = {
  ACCESS_TOKEN_EXPIRY,
  REFRESH_TOKEN_EXPIRY,
  generateAccessToken,
  generateRefreshToken,
  verifyToken,
  blacklistToken,
  isBlacklisted,
  storeRefreshToken,
  validateStoredRefreshToken,
  invalidateRefreshToken,
  revokeTokensIssuedBefore,
  isUserTokenRevoked
};
