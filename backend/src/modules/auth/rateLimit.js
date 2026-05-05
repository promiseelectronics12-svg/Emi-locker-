const { rateLimit } = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const redis = require('../../config/redis');

const RATE_LIMIT_WINDOW = 15 * 60 * 1000;
const MAX_LOGIN_ATTEMPTS = 100;
const MAX_2FA_ATTEMPTS = 100;

function createRedisStore(prefix) {
  // Use memory store by default for local development to prevent boot crashes
  return undefined;
}

function buildErrorPayload(message, code = 'RATE_LIMITED') {
  return {
    status: 'error',
    code,
    message
  };
}

const loginLimiter = rateLimit({
  windowMs: RATE_LIMIT_WINDOW,
  limit: MAX_LOGIN_ATTEMPTS,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  store: createRedisStore('rl:login:'),
  handler: (req, res) => {
    const retryAfter = req.rateLimit?.resetTime
      ? Math.max(1, Math.ceil((req.rateLimit.resetTime.getTime() - Date.now()) / 1000))
      : Math.ceil(RATE_LIMIT_WINDOW / 1000);

    res.set('Retry-After', String(retryAfter));
    return res.status(429).json(buildErrorPayload('Too many login attempts. Please try again later.'));
  }
});

const verify2FALimiter = rateLimit({
  windowMs: RATE_LIMIT_WINDOW,
  limit: MAX_2FA_ATTEMPTS,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  store: createRedisStore('rl:2fa:'),
  handler: (req, res) => {
    const retryAfter = req.rateLimit?.resetTime
      ? Math.max(1, Math.ceil((req.rateLimit.resetTime.getTime() - Date.now()) / 1000))
      : Math.ceil(RATE_LIMIT_WINDOW / 1000);

    res.set('Retry-After', String(retryAfter));
    return res.status(429).json(buildErrorPayload('Too many 2FA verification attempts. Please try again later.'));
  }
});

module.exports = {
  RATE_LIMIT_WINDOW,
  MAX_LOGIN_ATTEMPTS,
  MAX_2FA_ATTEMPTS,
  loginLimiter,
  verify2FALimiter
};
