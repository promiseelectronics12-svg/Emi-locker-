const Queue = require('bull');
const cron = require('node-cron');
const logger = require('../../utils/logger');
const { createClient } = require('../../config/redis');
const db = require('../../config/database');

// Bull createClient factory — all internal ioredis connections get error handlers
const bullCreateClient = (type) => {
  const c = createClient();
  c.on('error', (err) => logger.warn(`Bull Redis (${type}) error: ${err.message}`));
  return c;
};

const FRAUD_WINDOW_DAYS = 5;
const FRAUD_WINDOW_MS = FRAUD_WINDOW_DAYS * 24 * 60 * 60 * 1000;

let fraudWindowQueue = null;
let adminNotifyQueue = null;
let amapiRetryQueue = null;
let cronFallbackActive = false;

// ============================================================
// BULL QUEUES — primary scheduling mechanism
// ============================================================

function getFraudWindowQueue() {
  if (!fraudWindowQueue) {
    fraudWindowQueue = new Queue('decoupling-fraud-window', {
      createClient: bullCreateClient,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 60000 },
        removeOnComplete: 100,
        removeOnFail: 50
      }
    });

    fraudWindowQueue.on('error', (err) => {
      logger.error('Decoupling fraud window queue error:', err);
    });

    fraudWindowQueue.on('failed', (job, err) => {
      logger.error(`Fraud window job ${job.id} failed:`, err);
    });
  }
  return fraudWindowQueue;
}

function getAdminNotifyQueue() {
  if (!adminNotifyQueue) {
    adminNotifyQueue = new Queue('decoupling-admin-notify', {
      createClient: bullCreateClient,
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 60000 },
        removeOnComplete: 100,
        removeOnFail: 50
      }
    });

    adminNotifyQueue.on('error', (err) => {
      logger.error('Decoupling admin notify queue error:', err);
    });

    adminNotifyQueue.on('failed', (job, err) => {
      logger.error(`Admin notify job ${job.id} failed:`, err);
    });
  }
  return adminNotifyQueue;
}

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
// SCHEDULE — add delayed jobs to Bull queues (5-day delay)
// ============================================================

async function scheduleFraudWindowCheck(deviceId) {
  const queue = getFraudWindowQueue();
  const existingJob = await queue.getJob(`fraud-window-${deviceId}`);
  if (existingJob) {
    await existingJob.remove();
  }

  const job = await queue.add(
    'fraud-window-expired',
    { deviceId },
    {
      delay: FRAUD_WINDOW_MS,
      jobId: `fraud-window-${deviceId}`
    }
  );

  logger.info(`Fraud window check scheduled for device ${deviceId}`, {
    jobId: job.id,
    delay: FRAUD_WINDOW_MS,
    expiresAt: new Date(Date.now() + FRAUD_WINDOW_MS).toISOString()
  });

  return job;
}

async function scheduleAdminNotification(deviceId) {
  const queue = getAdminNotifyQueue();
  const existingJob = await queue.getJob(`admin-notify-${deviceId}`);
  if (existingJob) {
    await existingJob.remove();
  }

  const job = await queue.add(
    'notify-admin-decouple',
    { deviceId },
    {
      delay: FRAUD_WINDOW_MS,
      jobId: `admin-notify-${deviceId}`
    }
  );

  logger.info(`Admin notification scheduled for device ${deviceId}`, {
    jobId: job.id,
    delay: FRAUD_WINDOW_MS,
    notifyAt: new Date(Date.now() + FRAUD_WINDOW_MS).toISOString()
  });

  return job;
}

// ============================================================
// CANCEL — remove delayed jobs (e.g. when fraud is flagged)
// ============================================================

async function cancelFraudWindowCheck(deviceId) {
  const queue = getFraudWindowQueue();
  const job = await queue.getJob(`fraud-window-${deviceId}`);
  if (job) {
    await job.remove();
    logger.info(`Fraud window check cancelled for device ${deviceId}`, { jobId: job.id });
  }
}

async function cancelAdminNotification(deviceId) {
  const queue = getAdminNotifyQueue();
  const job = await queue.getJob(`admin-notify-${deviceId}`);
  if (job) {
    await job.remove();
    logger.info(`Admin notification cancelled for device ${deviceId}`, { jobId: job.id });
  }
}

// ============================================================
// PROCESSORS — register handlers for Bull queue jobs
// ============================================================

function registerFraudWindowProcessor(handler) {
  const queue = getFraudWindowQueue();
  queue.process('fraud-window-expired', async (job) => {
    const { deviceId } = job.data;
    logger.info(`Processing fraud window expiration for device ${deviceId}`);
    return handler(deviceId);
  });
  logger.info('Fraud window processor registered');
}

function registerAdminNotifyProcessor(handler) {
  const queue = getAdminNotifyQueue();
  queue.process('notify-admin-decouple', async (job) => {
    const { deviceId } = job.data;
    logger.info(`Processing admin notification for device ${deviceId}`);
    return handler(deviceId);
  });
  logger.info('Admin notify processor registered');
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
// CRON FALLBACK — catches missed Bull jobs
// Runs every 15 minutes, scans DB for expired windows
// that weren't caught by Bull (e.g. Redis down, server restart)
// ============================================================

function startCronFallback(fraudWindowHandler, adminNotifyHandler) {
  if (cronFallbackActive) return;

  // Every 15 minutes — check for expired fraud windows
  cron.schedule(
    '*/15 * * * *',
    async () => {
      try {
        const { DECOUPLING_STATES } = require('./decouplingModel');

        // Find devices where fraud window expired but state didn't transition
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
            logger.info(
              `Cron fallback: processing expired fraud window for device ${row.device_id}`
            );
            await fraudWindowHandler(row.device_id);
          } catch (err) {
            logger.error(`Cron fallback: failed to process device ${row.device_id}:`, err);
          }
        }
      } catch (err) {
        logger.error('Cron fallback scan failed:', err);
      }
    },
    { scheduled: true, timezone: process.env.TZ || 'UTC' }
  );

  cronFallbackActive = true;
  logger.info('Decoupling cron fallback started (every 15 minutes)');
}

// ============================================================
// QUEUE STATS
// ============================================================

async function getQueueStats() {
  const fwQueue = getFraudWindowQueue();
  const anQueue = getAdminNotifyQueue();

  const [fwWaiting, fwDelayed, fwActive, anWaiting, anDelayed, anActive] = await Promise.all([
    fwQueue.getWaitingCount(),
    fwQueue.getDelayedCount(),
    fwQueue.getActiveCount(),
    anQueue.getWaitingCount(),
    anQueue.getDelayedCount(),
    anQueue.getActiveCount()
  ]);

  return {
    fraudWindow: { waiting: fwWaiting, delayed: fwDelayed, active: fwActive },
    adminNotify: { waiting: anWaiting, delayed: anDelayed, active: anActive }
  };
}

// ============================================================
// SHUTDOWN — clean queue close
// ============================================================

async function close() {
  if (fraudWindowQueue) {
    await fraudWindowQueue.close();
    fraudWindowQueue = null;
  }
  if (adminNotifyQueue) {
    await adminNotifyQueue.close();
    adminNotifyQueue = null;
  }
  if (amapiRetryQueue) {
    await amapiRetryQueue.close();
    amapiRetryQueue = null;
  }
  logger.info('Decoupling scheduler queues closed');
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
  getQueueStats,
  close
};
