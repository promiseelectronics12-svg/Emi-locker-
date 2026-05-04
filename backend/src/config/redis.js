const Redis = require('ioredis');

const redis = new Redis(process.env.REDIS_URL || process.env.REDIS_TLS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: null,
  enableOfflineQueue: false,
  retryStrategy(times) {
    const delay = Math.min(times * 50, 2000);
    return delay;
  },
  reconnectOnError(err) {
    const targetError = 'READONLY';
    if (err.message.includes(targetError)) {
      return true;
    }
    return false;
  }
});

redis.on('error', (err) => {
  console.error('Redis connection error:', err);
  if (err.code === 'ECONNREFUSED' && redis.status !== 'ready') {
    console.error('WARNING: Could not connect to Redis at startup. Caching and rate-limiting may fail, but server will remain online.');
    // process.exit(1); // Disabled for local testing without Redis
  }
});

redis.on('connect', () => {
  console.log('Redis connected');
});

module.exports = redis;