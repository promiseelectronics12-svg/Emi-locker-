const cron = require('node-cron');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const locationService = require('./locationService');

const FULL_LOCK_LEVEL = 7;

class LocationSchedulerService {
  constructor() {
    this.jobs = [];
    this.started = false;
  }

  start() {
    if (this.started) {
      logger.warn('Location scheduler already started');
      return;
    }

    const job = cron.schedule('0 */6 * * *', async () => {
      logger.info('Scheduled auto-location check triggered');
      await this.checkDevicesInFullLock();
    }, { scheduled: true, timezone: process.env.TZ || 'UTC' });

    this.jobs.push(job);
    this.started = true;
    logger.info('Location scheduler started — auto-location every 6 hours');
  }

  stop() {
    this.jobs.forEach(job => job.stop());
    this.jobs = [];
    this.started = false;
    logger.info('Location scheduler stopped');
  }

  async checkDevicesInFullLock() {
    try {
      const result = await db.query(
        `SELECT d.id, d.imei, d.serial_number, d.fcm_token, d.dealer_id
         FROM devices d
         WHERE d.status = 'locked'
           AND d.lock_level >= $1
           AND d.status != 'decoupled'`,
        [FULL_LOCK_LEVEL]
      );

      logger.info(`Checking ${result.rows.length} devices in Full Lock for auto-location`);

      for (const device of result.rows) {
        try {
          const hasActiveGeofence = await db.query(
            `SELECT id FROM geofences WHERE device_id = $1 AND enabled = true`,
            [device.id]
          );

          if (hasActiveGeofence.rows.length > 0) {
            await locationService.pullLocationNow(device.id, 'scheduled_6h_check_with_geofence', 'system');
          } else {
            await locationService.pullLocationNow(device.id, 'scheduled_6h_check', 'system');
          }
        } catch (error) {
          logger.error(`Failed to process auto-location for device ${device.id}:`, error);
        }
      }

      logger.info('Auto-location check completed');
    } catch (error) {
      logger.error('Auto-location check failed:', error);
    }
  }

  async handleDeviceLockChange(deviceId, lockLevel) {
    if (lockLevel >= FULL_LOCK_LEVEL) {
      logger.info(`Device ${deviceId} entered Full Lock — scheduling auto-location`);
      await locationService.scheduleAutoLocation(deviceId);
    } else {
      logger.info(`Device ${deviceId} exited Full Lock — cancelling auto-location`);
      await locationService.cancelAutoLocation(deviceId);
    }
  }

  async syncScheduledLocations() {
    try {
      const result = await db.query(
        `SELECT d.id, d.imei, d.fcm_token, d.lock_level
         FROM devices d
         WHERE d.status = 'locked'
           AND d.lock_level >= $1
           AND d.status != 'decoupled'`,
        [FULL_LOCK_LEVEL]
      );

      for (const device of result.rows) {
        const hasJob = await this.hasScheduledJob(device.id);
        if (!hasJob) {
          await locationService.scheduleAutoLocation(device.id);
          logger.info(`Re-scheduled auto-location for device ${device.id}`);
        }
      }
    } catch (error) {
      logger.error('Failed to sync scheduled locations:', error);
    }
  }

  async hasScheduledJob(deviceId) {
    try {
      const queue = locationService.getAutoLocationQueue();
      const repeatableJobs = await queue.getRepeatableJobs();
      return repeatableJobs.some(job => job.name === `auto-location-${deviceId}`);
    } catch (error) {
      return false;
    }
  }
}

module.exports = new LocationSchedulerService();