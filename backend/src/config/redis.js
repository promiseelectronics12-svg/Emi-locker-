const Redis = require('ioredis');

// Simple in-memory store used as fallback when Redis is unavailable (dev only)
class MemoryStore {
  constructor() {
    this.store = new Map();
    this.sets = new Map();
    this.status = 'ready';
  }

  async ping() { return 'PONG'; }
  async quit() { return 'OK'; }

  async setex(key, ttlSeconds, value) {
    this.store.set(key, { value, expiresAt: Date.now() + ttlSeconds * 1000 });
    return 'OK';
  }

  async set(key, value) {
    this.store.set(key, { value, expiresAt: null });
    return 'OK';
  }

  async get(key) {
    const entry = this.store.get(key);
    if (!entry) return null;
    if (entry.expiresAt && Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return null;
    }
    return entry.value;
  }

  async del(key) {
    this.store.delete(key);
    this.sets.delete(key);
    return 1;
  }

  async expire(key, ttlSeconds) {
    const entry = this.store.get(key);
    if (entry) entry.expiresAt = Date.now() + ttlSeconds * 1000;
    return 1;
  }

  async ttl(key) {
    const entry = this.store.get(key);
    if (!entry || !entry.expiresAt) return -1;
    const remaining = Math.ceil((entry.expiresAt - Date.now()) / 1000);
    return remaining > 0 ? remaining : -2;
  }

  async incr(key) {
    const current = await this.get(key);
    const next = (parseInt(current || '0', 10) + 1).toString();
    const entry = this.store.get(key);
    this.store.set(key, { value: next, expiresAt: entry?.expiresAt || null });
    return parseInt(next, 10);
  }

  async sadd(key, ...members) {
    if (!this.sets.has(key)) this.sets.set(key, new Set());
    members.forEach(m => this.sets.get(key).add(m));
    return members.length;
  }

  async smembers(key) {
    return Array.from(this.sets.get(key) || []);
  }

  async srem(key, ...members) {
    const s = this.sets.get(key);
    if (!s) return 0;
    members.forEach(m => s.delete(m));
    return members.length;
  }

  async exists(key) {
    const entry = this.store.get(key);
    if (!entry) return 0;
    if (entry.expiresAt && Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return 0;
    }
    return 1;
  }

  on() { return this; }
}

let redis;

try {
  redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
    maxRetriesPerRequest: null,
    enableOfflineQueue: false,
    connectTimeout: 3000,
    lazyConnect: true,
    retryStrategy(times) {
      if (times > 3) return null; // stop retrying after 3 attempts
      return Math.min(times * 200, 1000);
    },
  });

  redis.on('error', (err) => {
    if (err.code === 'ECONNREFUSED' || err.code === 'ENOTFOUND') {
      // silently switch to memory store
    } else {
      console.error('Redis error:', err.message);
    }
  });

  redis.on('connect', () => console.log('Redis connected'));

  // Try to connect; if it fails, fall back to in-memory
  redis.connect().catch(() => {
    console.warn('WARNING: Redis unavailable — using in-memory store. Do NOT use in production.');
    redis = new MemoryStore();
  });

} catch (err) {
  console.warn('WARNING: Redis init failed — using in-memory store. Do NOT use in production.');
  redis = new MemoryStore();
}

// Export a proxy so callers always get the current redis instance (real or memory)
const handler = {
  get(target, prop) {
    return typeof redis[prop] === 'function'
      ? redis[prop].bind(redis)
      : redis[prop];
  }
};

module.exports = new Proxy({}, handler);
