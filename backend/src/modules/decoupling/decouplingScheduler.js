const Queue = require('bull');
const Redis = require('ioredis');
const cron = require('node-cron');
const logger = require('../../utils/logger');
const db = require('../../config/database');

// Fraud-window and admin-notify delayed jobs are handled by a DB cron scan
// (every 15 min, queries fraud_window_ends_at). Bull is kept only for
// AMAPI retry which needs short exponential retries (minutes, not days).
// This avoids Bull/Upstash serverless-Redis incompatibility.

const FRAUD_WINDOW_DAYS = 5;
const FRAUD_WINDOW_MS = FRAUD_WINDOW_DAYS * 24 * 60 * 60 * 1000;

let amapiRetryQueue = null;
let cronActive = false;

// ============================================================
// BULL CLIENT — AMAPI retry queue only
// BULL_REDIS_URL: set this to a traditional Redis (non-serverless)
// if available. Falls back to UPSTASH_REDIS_URL with
// enableReadyCheck: false which works with serverless Redis.
// ============================================================

const bullRedisUrl =
  process.env.BULL_REDIS_URL ||
  process.env.UPSTASH_REDIS_URL ||
  process.env.REDIS_URL ||
  'redis://localhost:6379';

const bullTlsOptions = bullRedisUrl.startsWith('rediss://')
  ? { tls: { rejectUnauthorized: true } }
  : {};

const bullCreateClient = (type) => {
  const c = new Redis(bullRedisUrl, {
    ...bullTlsOptions,
    enableReadyCheck: false,
    maxRetriesPerRequest: null,
    enableOfflineQueue: false,
    connectTimeout: 5000,
    retryStrategy(times) {
      if (times > 10) return null;
      return Math.min(times * 300, 3000);
    }
  });
  c.on('error', (err) => logger.warn(`Bull Redis (${type}) error: ${err.message}`));
  return c;
};

// ============================================================
// AMAPI RETRY QUEUE
// ============================================================

function getAMAPIRetryQueue() {
  if (!amapiRetryQueue) {
    amapiRetryQueue = new Queue('decoupling-amapi-retry', {
      createClient: bullCreateClient,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 60000 },
        removeOnComplete: 100,
        removeOnFail: 50
      }
    });
    amapiRetryQueue.on('error', (err) => {
      logger.error('Decoupling AMAPI retry queue error:', err);
    });
  }
  return amapiRetryQueue;
}

// ============================================================
// SCHEDULE stubs — fraud_window_ends_at in DB is the source of
// truth; the 15-min cron picks it up. Callers unchanged.
// ============================================================

async function scheduleFraudWindowCheck(deviceId) {
  logger.debug(`Fraud window for device ${deviceId} tracked via DB (fraud_window_ends_at)`);
}

async function scheduleAdminNotification(deviceId) {
  logger.debug(`Admin notification for device ${deviceId} tracked via DB (fraud_window_ends_at)`);
}

// ============================================================
// CANCEL stubs — cron checks fraud_flag = false naturally
// ============================================================

async function cancelFraudWindowCheck(_deviceId) {}

async function cancelAdminNotification(_deviceId) {}

// ============================================================
// PROCESSORS
// ============================================================

function registerFraudWindowProcessor(_handler) {
  // Fraud window processed by DB cron (startCronFallback), not Bull
}

function registerAdminNotifyProcessor(_handler) {
  // Admin notify processed by DB cron (startCronFallback), not Bull
}

function registerAMAPIRetryProcessor(handler) {
  const queue = getAMAPIRetryQueue();
  queue.process('amapi-retry', async (job) => {
    const { deviceId, attempt } = job.data;
    logger.info(`Processing AMAPI retry for device ${deviceId}, attempt ${attempt}`);
    return handler(deviceId, attempt);
  });
  logger.info('AMAPI retry processor registered');
}

// ============================================================
// DB CRON — primary scheduler for fraud-window + admin-notify
// Every 15 min, scans for expired fraud windows.
// fraudWindowHandler: transitions device to PENDING_ADMIN_DECOUPLE
//   (onPendingAdminDecouple already notifies admins — no separate
//   admin notify job needed)
// ============================================================

function startCronFallback(fraudWindowHandler) {
  if (cronActive) return;

  cron.schedule(
    '*/15 * * * *',
    async () => {
      try {
        const { DECOUPLING_STATES } = require('./decouplingModel');

        const expired = await db.query(
          `SELECT d.device_id
           FROM decoupling d
           WHERE d.state = $1
             AND d.fraud_flag = false
             AND d.fraud_window_ends_at <= NOW()
           LIMIT 50`,
          [DECOUPLING_STATES.DEALER_NOTIFIED]
        );

        for (const row of expired.rows) {
          try {
            logger.info(`DB cron: processing expired fraud window for device ${row.device_id}`);
            await fraudWindowHandler(row.device_id);
          } catch (err) {
            logger.error(`DB cron: failed to process device ${row.device_id}:`, err);
          }
        }
      } catch (err) {
        logger.error('Decoupling cron scan failed:', err);
      }
    },
    { scheduled: true, timezone: process.env.TZ || 'UTC' }
  );

  cronActive = true;
  logger.info('Decoupling DB cron started (every 15 min)');
}

function isCronActive() {
  return cronActive;
}

// ============================================================
// QUEUE STATS
// ============================================================

async function getQueueStats() {
  const queue = getAMAPIRetryQueue();
  const [waiting, delayed, active] = await Promise.all([
    queue.getWaitingCount(),
    queue.getDelayedCount(),
    queue.getActiveCount()
  ]);
  return {
    amapiRetry: { waiting, delayed, active }
  };
}

// ============================================================
// SHUTDOWN
// ============================================================

async function close() {
  if (amapiRetryQueue) {
    await amapiRetryQueue.close();
    amapiRetryQueue = null;
  }
  logger.info('Decoupling scheduler closed');
}

module.exports = {
  FRAUD_WINDOW_DAYS,
  FRAUD_WINDOW_MS,
  scheduleFraudWindowCheck,
  scheduleAdminNotification,
  cancelFraudWindowCheck,
  cancelAdminNotification,
  registerFraudWindowProcessor,
  registerAdminNotifyProcessor,
  registerAMAPIRetryProcessor,
  getAMAPIRetryQueue,
  startCronFallback,
  isCronActive,
  getQueueStats,
  close
};
