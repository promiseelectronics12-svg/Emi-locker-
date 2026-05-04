const { Redis } = require('ioredis');

const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

const DEALER_MESSAGE_LIMIT = 10;
const DEALER_MESSAGE_WINDOW_SECONDS = 24 * 60 * 60;

const ATOMIC_RATE_LIMIT_SCRIPT = `
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])

local current = redis.call('INCR', key)
if current == 1 then
  redis.call('EXPIRE', key, window)
end

local ttl = redis.call('TTL', key)
local resetAt = tonumber(ARGV[3]) + (ttl > 0 and ttl or window) * 1000

if current > limit then
  return {0, current - 1, limit, resetAt}
else
  return {1, current, limit, resetAt}
end
`;

async function checkAndIncrementDealerMessageRateLimit(deviceId) {
  const key = `dealer_message:${deviceId}:${getDateKey()}`;
  const now = Date.now();

  try {
    const result = await redis.eval(
      ATOMIC_RATE_LIMIT_SCRIPT,
      1,
      key,
      DEALER_MESSAGE_LIMIT.toString(),
      DEALER_MESSAGE_WINDOW_SECONDS.toString(),
      now.toString()
    );

    return {
      allowed: result[0] === 1,
      currentCount: result[1],
      limit: result[2],
      resetAt: new Date(result[3]),
    };
  } catch (error) {
    console.error('Redis error in checkAndIncrementDealerMessageRateLimit - rejecting request:', error.message);
    return {
      allowed: false,
      currentCount: 0,
      limit: DEALER_MESSAGE_LIMIT,
      resetAt: new Date(now + DEALER_MESSAGE_WINDOW_SECONDS * 1000),
    };
  }
}

async function resetDealerMessageCount(deviceId) {
  const key = `dealer_message:${deviceId}:${getDateKey()}`;
  await redis.del(key);
}

function getDateKey() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

async function getDealerMessageStats(deviceId) {
  const result = await checkDealerMessageRateLimit(deviceId);
  return {
    todayCount: result.currentCount,
    limit: result.limit,
    remaining: Math.max(0, result.limit - result.currentCount),
    resetAt: result.resetAt,
  };
}

async function checkDealerMessageRateLimit(deviceId) {
  const key = `dealer_message:${deviceId}:${getDateKey()}`;

  const currentCount = await redis.get(key);
  const count = currentCount ? parseInt(currentCount, 10) : 0;

  const ttl = await redis.ttl(key);
  const resetAt = new Date(Date.now() + (ttl > 0 ? ttl * 1000 : DEALER_MESSAGE_WINDOW_SECONDS * 1000));

  return {
    allowed: count < DEALER_MESSAGE_LIMIT,
    currentCount: count,
    limit: DEALER_MESSAGE_LIMIT,
    resetAt,
  };
}

module.exports = {
  checkAndIncrementDealerMessageRateLimit,
  resetDealerMessageCount,
  getDealerMessageStats,
  checkDealerMessageRateLimit,
};