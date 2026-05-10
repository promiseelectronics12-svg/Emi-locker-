const recentMessages = new Map();

const DEALER_MESSAGE_LIMIT = 10;
const DEALER_MESSAGE_WINDOW_SECONDS = 24 * 60 * 60;
const DUPLICATE_WINDOW_MS = 10 * 1000;

function keyFor(deviceId) {
  const now = new Date();
  return `${deviceId}:${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}-${String(now.getUTCDate()).padStart(2, '0')}`;
}

async function checkAndIncrementDealerMessageRateLimit(deviceId, message = '') {
  const key = keyFor(deviceId);
  const now = Date.now();
  const existing = recentMessages.get(key);

  if (
    existing &&
    existing.message === message &&
    now - existing.lastSentAt < DUPLICATE_WINDOW_MS
  ) {
    return {
      allowed: false,
      currentCount: existing.currentCount,
      limit: DEALER_MESSAGE_LIMIT,
      resetAt: existing.resetAt,
      error: 'Duplicate message cooldown active'
    };
  }

  const resetAt = existing?.resetAt && existing.resetAt.getTime() > now
    ? existing.resetAt
    : new Date(now + DEALER_MESSAGE_WINDOW_SECONDS * 1000);

  recentMessages.set(key, {
    currentCount: (existing?.currentCount || 0) + 1,
    message,
    lastSentAt: now,
    resetAt
  });

  return {
    allowed: true,
    currentCount: recentMessages.get(key).currentCount,
    limit: DEALER_MESSAGE_LIMIT,
    resetAt
  };
}

async function resetDealerMessageCount(deviceId) {
  recentMessages.delete(keyFor(deviceId));
}

async function checkDealerMessageRateLimit(deviceId) {
  const existing = recentMessages.get(keyFor(deviceId));
  const now = Date.now();
  return {
    allowed: true,
    currentCount: existing && existing.resetAt.getTime() > now ? existing.currentCount : 0,
    limit: DEALER_MESSAGE_LIMIT,
    resetAt: existing?.resetAt || new Date(now + DEALER_MESSAGE_WINDOW_SECONDS * 1000)
  };
}

async function getDealerMessageStats(deviceId) {
  const result = await checkDealerMessageRateLimit(deviceId);
  return {
    todayCount: result.currentCount,
    limit: result.limit,
    remaining: Math.max(0, result.limit - result.currentCount),
    resetAt: result.resetAt
  };
}

module.exports = {
  checkAndIncrementDealerMessageRateLimit,
  resetDealerMessageCount,
  getDealerMessageStats,
  checkDealerMessageRateLimit
};
