const Redis = require('ioredis');

const isDev = process.env.NODE_ENV !== 'production';

// ── Development-only in-memory fallback ──────────────────────────────────────
// Only used when no DragonflyDB/Redis URL is configured in local dev.
// NEVER active in production — the process will crash instead (see below).
class MemoryStore {
  constructor() {
    this.store = new Map();
    this.sets  = new Map();
    this.status = 'ready';
  }

  async ping()                       { return 'PONG'; }
  async quit()                       { return 'OK'; }

  async set(key, value)              { this.store.set(key, { value, expiresAt: null }); return 'OK'; }
  async setex(key, ttl, value)       { this.store.set(key, { value, expiresAt: Date.now() + ttl * 1000 }); return 'OK'; }

  async get(key) {
    const e = this.store.get(key);
    if (!e) return null;
    if (e.expiresAt && Date.now() > e.expiresAt) { this.store.delete(key); return null; }
    return e.value;
  }

  async del(key)                     { this.store.delete(key); this.sets.delete(key); return 1; }

  async expire(key, ttl) {
    const e = this.store.get(key);
    if (e) e.expiresAt = Date.now() + ttl * 1000;
    return 1;
  }

  async ttl(key) {
    const e = this.store.get(key);
    if (!e || !e.expiresAt) return -1;
    const rem = Math.ceil((e.expiresAt - Date.now()) / 1000);
    return rem > 0 ? rem : -2;
  }

  async incr(key) {
    const cur  = await this.get(key);
    const next = (parseInt(cur || '0', 10) + 1).toString();
    const e    = this.store.get(key);
    this.store.set(key, { value: next, expiresAt: e?.expiresAt || null });
    return parseInt(next, 10);
  }

  async sadd(key, ...members) {
    if (!this.sets.has(key)) this.sets.set(key, new Set());
    members.forEach(m => this.sets.get(key).add(m));
    return members.length;
  }

  async smembers(key) { return Array.from(this.sets.get(key) || []); }

  async srem(key, ...members) {
    const s = this.sets.get(key);
    if (!s) return 0;
    members.forEach(m => s.delete(m));
    return members.length;
  }

  async exists(key) {
    const e = this.store.get(key);
    if (!e) return 0;
    if (e.expiresAt && Date.now() > e.expiresAt) { this.store.delete(key); return 0; }
    return 1;
  }

  on() { return this; }
}

// ── DragonflyDB / Redis connection ────────────────────────────────────────────
// DragonflyDB is 100% Redis-protocol compatible — ioredis connects to it
// identically. Just point DRAGONFLY_URL at your Dragonfly Cloud instance.
// Falls back to REDIS_URL for backward compatibility.

const connectionUrl =
  process.env.DRAGONFLY_URL    ||
  process.env.UPSTASH_REDIS_URL ||
  process.env.REDIS_URL         ||
  (isDev ? 'redis://localhost:6379' : null);

if (!connectionUrl) {
  console.error(
    'FATAL: No DragonflyDB/Redis URL configured.\n' +
    'Set DRAGONFLY_URL in your environment.\n' +
    'Get a free instance at: https://cloud.dragonflydb.io'
  );
  process.exit(1);
}

// TLS is required for Dragonfly Cloud (rediss://) — ioredis enables it
// automatically when the URL scheme is "rediss://".
const tlsOptions = connectionUrl.startsWith('rediss://')
  ? { tls: { rejectUnauthorized: true } }
  : {};

const client = new Redis(connectionUrl, {
  ...tlsOptions,
  maxRetriesPerRequest: null,
  enableOfflineQueue: false,
  connectTimeout: 5000,
  // In production: retry up to 10 times with exponential back-off (max 3s),
  // then crash so the process manager (PM2/Docker) restarts cleanly.
  // In dev: stop after 3 attempts and fall through to MemoryStore.
  retryStrategy(times) {
    const limit = isDev ? 3 : 10;
    if (times > limit) return null;
    return Math.min(times * 300, 3000);
  },
});

client.on('connect',        ()    => console.log('DragonflyDB connected'));
client.on('reconnecting',   ()    => console.warn('DragonflyDB reconnecting…'));
client.on('error',          (err) => {
  // Log every error — never swallow silently
  console.error('DragonflyDB error:', err.message);
});

// ── Export ────────────────────────────────────────────────────────────────────
// We use a lazy-connect pattern so Bull queue workers (which duplicate this
// connection) get a fresh ioredis instance via createClient() below.

let _redis = null;

async function connectRedis() {
  if (_redis) return _redis;

  try {
    await client.connect();
    _redis = client;
    return _redis;
  } catch (err) {
    if (!isDev) {
      console.error('FATAL: DragonflyDB connection failed —', err.message);
      console.error('The server cannot start without DragonflyDB.');
      console.error('Check DRAGONFLY_URL and your Dragonfly Cloud instance.');
      process.exit(1);
    }

    // Development only: fall back to MemoryStore with loud warnings
    console.warn('');
    console.warn('⚠️  DragonflyDB unavailable — using in-memory store.');
    console.warn('⚠️  Rate limiting, sessions and replay protection are DISABLED.');
    console.warn('⚠️  This is acceptable for local development ONLY.');
    console.warn('⚠️  Set DRAGONFLY_URL before deploying to production.');
    console.warn('');
    _redis = new MemoryStore();
    return _redis;
  }
}

// Eagerly connect on import so the server fails fast if DragonflyDB is down
connectRedis().catch(() => {}); // errors already handled inside connectRedis

// Proxy: callers do `redis.get(...)` without awaiting connectRedis() themselves
const proxy = new Proxy({}, {
  get(_target, prop) {
    const instance = _redis || client;
    const val = instance[prop];
    return typeof val === 'function' ? val.bind(instance) : val;
  },
});

// createClient() — used by Bull queues to get a dedicated ioredis instance.
// Bull requires separate subscriber + blocking connections; sharing the main
// client with it causes ENOTCONN errors.
function createClient() {
  return new Redis(connectionUrl, {
    ...tlsOptions,
    maxRetriesPerRequest: null,
    enableOfflineQueue: false,
    connectTimeout: 5000,
    retryStrategy(times) {
      if (times > 10) return null;
      return Math.min(times * 300, 3000);
    },
  });
}

module.exports = proxy;
module.exports.createClient  = createClient;
module.exports.connectRedis  = connectRedis;
