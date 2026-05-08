const db = require('../config/database');
const {
  verifyToken,
  isBlacklisted,
  isUserTokenRevoked
} = require('../modules/auth/jwt');
const logger = require('../utils/logger');

function sendAuthError(res, code, message) {
  return res.status(401).json({
    status: 'error',
    code,
    message
  });
}

function extractBearerToken(req) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    return null;
  }

  return authHeader.slice(7).trim();
}

async function authenticateToken(req, res, next) {
  const token = extractBearerToken(req);

  if (!token) {
    await logSecurityEvent('AUTH_MISSING_TOKEN', { ip: req.ip, path: req.path });
    return sendAuthError(res, 'ACCESS_TOKEN_REQUIRED', 'Access token required');
  }

  try {
    if (await isBlacklisted(token)) {
      await logSecurityEvent('AUTH_REVOKED_TOKEN', { ip: req.ip, path: req.path });
      return sendAuthError(res, 'TOKEN_REVOKED', 'Token has been revoked');
    }

    const decoded = verifyToken(token, 'access');

    if (await isUserTokenRevoked(decoded)) {
      await logSecurityEvent('AUTH_REVOKED_BY_USER_EVENT', { ip: req.ip, path: req.path, userId: decoded.userId });
      return sendAuthError(res, 'TOKEN_REVOKED', 'Token has been revoked');
    }

    const result = await db.query(
      'SELECT id, email, role, status FROM users WHERE id = $1',
      [decoded.userId]
    );

    if (result.rows.length === 0) {
      await logSecurityEvent('AUTH_USER_NOT_FOUND', { ip: req.ip, path: req.path, userId: decoded.userId });
      return sendAuthError(res, 'USER_NOT_FOUND', 'User not found');
    }

    const user = result.rows[0];
    if (user.status !== 'active') {
      await logSecurityEvent('AUTH_INACTIVE_ACCOUNT', { ip: req.ip, path: req.path, userId: decoded.userId });
      return sendAuthError(res, 'ACCOUNT_INACTIVE', 'Account is not active');
    }

    req.user = {
      id: decoded.userId,
      email: user.email,
      role: user.role,
      jti: decoded.jti
    };

    return next();
  } catch (error) {
    if (error.code === 'TOKEN_EXPIRED') {
      await logSecurityEvent('AUTH_EXPIRED_TOKEN', { ip: req.ip, path: req.path });
      return sendAuthError(res, 'TOKEN_EXPIRED', 'Token expired');
    }

    if (error.code === 'INVALID_TOKEN' || error.code === 'INVALID_TOKEN_TYPE') {
      await logSecurityEvent('AUTH_INVALID_TOKEN', { ip: req.ip, path: req.path });
      return sendAuthError(res, 'INVALID_TOKEN', 'Invalid token');
    }

    logger.error('Authentication error:', error);
    await logSecurityEvent('AUTH_FAILED', { ip: req.ip, path: req.path, error: error.message });
    return sendAuthError(res, 'AUTHENTICATION_FAILED', 'Authentication failed');
  }
}

async function logSecurityEvent(eventType, metadata) {
  try {
    await db.query(
      `INSERT INTO security_events (event_type, severity, actor, metadata, created_at)
       VALUES ($1, $2, $3, $4, NOW())`,
      [eventType, 'warning', metadata.userId || metadata.ip || 'unknown', JSON.stringify(metadata)]
    );
  } catch (error) {
    logger.error('Failed to log security event:', error);
  }
}

async function authenticateSocket(socket, next) {
  const authHeader = socket.handshake.headers?.authorization || '';
  const token = socket.handshake.auth?.token || (authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null);

  if (!token) {
    return next(new Error('Authentication token required'));
  }

  try {
    if (await isBlacklisted(token)) {
      return next(new Error('Token has been revoked'));
    }

    const decoded = verifyToken(token, 'access');
    if (await isUserTokenRevoked(decoded)) {
      return next(new Error('Token has been revoked'));
    }

    const result = await db.query(
      'SELECT id, email, role, status FROM users WHERE id = $1',
      [decoded.userId]
    );

    if (result.rows.length === 0 || result.rows[0].status !== 'active') {
      return next(new Error('User not found or inactive'));
    }

    socket.user = {
      id: decoded.userId,
      email: result.rows[0].email,
      role: result.rows[0].role,
      jti: decoded.jti
    };

    return next();
  } catch (error) {
    logger.error('Socket authentication error:', error);
    return next(new Error('Authentication failed'));
  }
}

function optionalAuth(req, res, next) {
  const token = extractBearerToken(req);
  if (!token) {
    return next();
  }

  return authenticateToken(req, res, next);
}

function requireRole(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ status: 'error', code: 'UNAUTHORIZED', message: 'User not authenticated' });
    }
    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ status: 'error', code: 'FORBIDDEN', message: 'Insufficient permissions' });
    }
    next();
  };
}

module.exports = {
  authenticateToken,
  authenticateSocket,
  optionalAuth,
  requireRole
};
