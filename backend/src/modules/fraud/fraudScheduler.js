const cron = require('node-cron');
const fraudService = require('./fraudService');
const db = require('../../config/database');
const sseService = require('../sse/sseService');
const logger = require('../../utils/logger');
const { getActiveAssignment } = require('../assignments/assignmentService');

let fraudDetectionTask = null;
let offlineCheckTask = null;
let locationRetentionTask = null;
let simMissingCheckTask = null;

function initFraudCronJobs() {
  logger.info('Initializing fraud detection cron jobs');

  fraudDetectionTask = cron.schedule('0 2 * * *', async () => {
    logger.info('Starting nightly fraud detection run');
    try {
      const results = await fraudService.runAllAnomalyDetections();
      logger.info('Nightly fraud detection completed', { results });
    } catch (error) {
      logger.error('Nightly fraud detection failed:', error);
    }
  }, {
    scheduled: true,
    timezone: 'Asia/Dhaka',
  });

  // Daily at 3 AM: purge location_reports older than 90 days, keep max 1000 per device
  locationRetentionTask = cron.schedule('0 3 * * *', async () => {
    try {
      await runLocationRetention();
    } catch (error) {
      logger.error('Location retention cleanup failed', { error: error.message });
    }
  }, { timezone: 'Asia/Dhaka' });

  // Every 30 min: devices silent on both internet AND SMS for 24h → fraud_suspected
  offlineCheckTask = cron.schedule('*/30 * * * *', async () => {
    try {
      await runOfflineFraudCheck();
    } catch (error) {
      logger.error('Offline fraud check failed', { error: error.message });
    }
  });

  // Every 5 min: devices with bound SIM absent > 5 min → lock
  simMissingCheckTask = cron.schedule('*/5 * * * *', async () => {
    try {
      await runSimMissingCheck();
    } catch (error) {
      logger.error('SIM missing check failed', { error: error.message });
    }
  });

  logger.info('Fraud detection cron jobs scheduled');
}

async function runOfflineFraudCheck() {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const result = await db.query(
    `SELECT d.id, d.dealer_id, d.device_name, d.imei
     FROM devices d
     WHERE d.status NOT IN ('fraud_suspected', 'locked', 'decoupled', 'decommissioned', 'disabled', 'suspended', 'pending')
       AND (d.last_seen_at IS NULL OR d.last_seen_at < $1)
       AND (d.last_sms_heartbeat_at IS NULL OR d.last_sms_heartbeat_at < $1)
       AND EXISTS (
         SELECT 1 FROM emi_schedules es
         WHERE es.device_id = d.id AND es.status = 'active'
       )`,
    [cutoff]
  );

  if (!result.rows.length) return;

  logger.info('Offline fraud check flagging devices', { count: result.rows.length });

  for (const device of result.rows) {
    try {
      await db.query(
        `UPDATE devices SET status = 'fraud_suspected', updated_at = NOW() WHERE id = $1`,
        [device.id]
      );
      const assignmentId = await getActiveAssignment(device.id);
      await db.query(
        `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, details)
         VALUES ($1, $2, 'FRAUD_SUSPECTED', 'system', $3)`,
        [device.id, assignmentId, JSON.stringify({ reason: 'offline_24h_no_sms', cutoff })]
      );
      try {
        if (device.dealer_id) {
          sseService.pushToDealer(device.dealer_id, 'fraud_suspected', {
            deviceId: device.id,
            deviceName: device.device_name,
            imei: device.imei,
            reason: 'offline_24h_no_sms'
          });
        }
      } catch (_) {}
    } catch (err) {
      logger.error('Failed to flag device as fraud_suspected', { deviceId: device.id, error: err.message });
    }
  }
}

async function runLocationRetention() {
  // Delete points older than 90 days
  const cutoff = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const aged = await db.query(
    `DELETE FROM location_reports WHERE recorded_at < $1`,
    [cutoff]
  );

  // For devices with >1000 points, keep only newest 1000
  const overflow = await db.query(
    `DELETE FROM location_reports
     WHERE id IN (
       SELECT id FROM (
         SELECT id, ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY recorded_at DESC) AS rn
         FROM location_reports
       ) ranked
       WHERE rn > 1000
     )`
  );

  logger.info('Location retention complete', {
    deletedAged: aged.rowCount,
    deletedOverflow: overflow.rowCount
  });
}

async function runSimMissingCheck() {
  // Grace period: 5 minutes. Devices where bound SIM has been absent
  // for more than 5 minutes → lock immediately.
  const graceCutoff = new Date(Date.now() - 5 * 60 * 1000).toISOString();

  const result = await db.query(
    `SELECT d.id, d.dealer_id, d.device_name, d.imei
     FROM devices d
     WHERE d.sim_missing_since IS NOT NULL
       AND d.sim_missing_since < $1
       AND d.status NOT IN ('locked', 'fraud_suspected', 'decoupled', 'decommissioned', 'disabled', 'suspended', 'pending')
       AND d.registered_phone IS NOT NULL`,
    [graceCutoff]
  );

  if (!result.rows.length) return;

  logger.info('SIM missing check locking devices', { count: result.rows.length });

  for (const device of result.rows) {
    try {
      await db.query(
        `UPDATE devices
         SET status = 'locked',
             lock_level = 'FULL',
             lock_reason = 'SIM_REMOVED',
             locked_at = COALESCE(locked_at, NOW()),
             updated_at = NOW()
         WHERE id = $1`,
        [device.id]
      );
      const assignmentId = await getActiveAssignment(device.id);
      await db.query(
        `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, permanent, details)
         VALUES ($1, $2, 'LOCKED', 'system', false, $3)`,
        [device.id, assignmentId, JSON.stringify({ reason: 'SIM_REMOVED', lock_level: 'FULL' })]
      );
      try {
        if (device.dealer_id) {
          sseService.pushToDealer(device.dealer_id, 'device_locked', {
            deviceId: device.id,
            deviceName: device.device_name,
            imei: device.imei,
            reason: 'SIM_REMOVED'
          });
        }
      } catch (_) {}
    } catch (err) {
      logger.error('Failed to lock device for SIM removal', { deviceId: device.id, error: err.message });
    }
  }
}

function stopFraudCronJobs() {
  if (fraudDetectionTask) fraudDetectionTask.stop();
  if (offlineCheckTask) offlineCheckTask.stop();
  if (locationRetentionTask) locationRetentionTask.stop();
  if (simMissingCheckTask) simMissingCheckTask.stop();
  logger.info('Fraud detection cron jobs stopped');
}

async function runFraudDetectionNow() {
  logger.info('Manual fraud detection triggered');
  return fraudService.runAllAnomalyDetections();
}

module.exports = {
  initFraudCronJobs,
  stopFraudCronJobs,
  runFraudDetectionNow,
  runOfflineFraudCheck,
  runLocationRetention,
  runSimMissingCheck,
};
