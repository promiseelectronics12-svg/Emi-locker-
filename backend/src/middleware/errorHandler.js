/**
 * Global Error Handler Middleware
 */
const logger = require('../utils/logger');
const errorStore = require('../utils/errorStore');

function buildErrorResponse(statusCode, code, message) {
  return {
    status: 'error',
    code,
    message
  };
}

function sendError(res, statusCode, code, message) {
  return res.status(statusCode).json(buildErrorResponse(statusCode, code, message));
}

// eslint-disable-next-line no-unused-vars
const errorHandler = (err, req, res, next) => {
  // 1. Log full error for internal tracking
  logger.error({
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    user: req.user ? req.user.id : 'anonymous'
  });

  // 2. Push to in-memory error store (admin panel + dev monitoring)
  errorStore.push(err, {
    method: req.method,
    path: req.path,
    userId: req.user ? req.user.id : null
  });

  // 3. Handle specific error types

  // PostgreSQL errors
  if (err.code === '23505') {
    // Unique violation
    return sendError(res, 409, 'CONFLICT', 'A resource with this identifier already exists.');
  }

  // JWT errors
  if (err.name === 'JsonWebTokenError') {
    return sendError(res, 401, 'INVALID_TOKEN', 'Invalid token provided.');
  }

  if (err.name === 'TokenExpiredError') {
    return sendError(res, 401, 'TOKEN_EXPIRED', 'Token has expired.');
  }

  // Validation errors
  if (err.name === 'ValidationError' || err.status === 400) {
    return sendError(res, 400, 'VALIDATION_ERROR', err.message);
  }

  // 4. Default to 500 Internal Server Error
  const isProduction = process.env.NODE_ENV === 'production';
  const statusCode = err.status || err.statusCode || 500;

  const response = buildErrorResponse(
    statusCode,
    statusCode === 500 ? 'INTERNAL_SERVER_ERROR' : err.name || 'ERROR',
    isProduction && statusCode === 500 ? 'An unexpected error occurred.' : err.message
  );

  // Never expose stack trace to client
  res.status(statusCode).json(response);
};

module.exports = errorHandler;
module.exports.buildErrorResponse = buildErrorResponse;
module.exports.sendError = sendError;
