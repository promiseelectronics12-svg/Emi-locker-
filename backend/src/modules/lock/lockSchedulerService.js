const cron = require('node-cron');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const lockDeliveryService = require('./lockDeliveryService');
const lockCommandService = require('./lockCommandService');

const LOCK_LEVELS = {
  NONE: 'NONE',
  REMINDER_MODE: 'REMINDER_MODE',
  PARTIAL_LOCK: 'PARTIAL_LOCK',
  FULL_LOCK: 'FULL_LOCK',
};

class LockSchedulerService {
  constructor() {
    this.jobs = [];
    this.started = false;
  }

  start() {
    if (this.started) {
      logger.warn('Lock scheduler already started');
      return;
    }

    const cronSchedule = process.env.AUTO_LOCK_CRON || '0 0 * * *';

    const dailyJob = cron.schedule(cronSchedule, async () => {
      logger.info('Auto-lock scheduler triggered');
      await this.runDailyCheck();
    }, { scheduled: true, timezone: process.env.TZ || 'UTC' });

    this.jobs.push(dailyJob);

    // Grace expiry check — runs every 5 minutes.
    // Finds devices whose dealer-issued grace period has expired and re-locks them.
    const graceJob = cron.schedule('*/5 * * * *', async () => {
      await this.runGraceExpiryCheck();
    }, { scheduled: true, timezone: process.env.TZ || 'UTC' });

    this.jobs.push(graceJob);

    this.started = true;
    logger.info(`Lock scheduler started with cron: ${cronSchedule} + grace expiry every 5 min`);
  }

  stop() {
    this.jobs.forEach(job => job.stop());
    this.jobs = [];
    this.started = false;
    logger.info('Lock scheduler stopped');
  }

  async runDailyCheck() {
    try {
      const devices = await db.query(
        `SELECT d.id, d.imei, d.fcm_token, d.amapi_device_name, d.lock_level,
                es.next_due_date, es.grace_period_days
         FROM devices d
         JOIN emi_schedules es ON d.id = es.device_id AND es.status = 'active'
         WHERE d.status NOT IN ('decoupled', 'disabled')
           AND es.next_due_date IS NOT NULL`
      );

      logger.info(`Auto-lock scheduler checking ${devices.rows.length} devices`);

      let processed = 0;
      let locked = 0;
      let notified = 0;
      let errors = 0;

      for (const device of devices.rows) {
        try {
          const result = await this.processDevice(device);
          processed++;
          if (result.locked) locked++;
          if (result.notified) notified++;
        } catch (error) {
          errors++;
          logger.error('Auto-lock device processing failed', {
            deviceId: device.id,
            error: error.message,
          });
        }
      }

      logger.info('Auto-lock scheduler completed', { processed, locked, notified, errors });
    } catch (error) {
      logger.error('Auto-lock scheduler run failed', { error: error.message });
    }
  }

  async processDevice(device) {
    const { id: deviceId, imei, next_due_date, grace_period_days } = device;
    const graceDays = grace_period_days || 7;

    const now = new Date();
    const dueDate = new Date(next_due_date);
    const overdueDays = Math.floor((now - dueDate) / (1000 * 60 * 60 * 24));

    const schedule = this.getScheduleAction(overdueDays);

    if (!schedule) {
      return { locked: false, notified: false };
    }

    switch (schedule.action) {
      case 'REMINDER_PUSH':
        await this.sendReminderNotification(deviceId, overdueDays);
        return { locked: false, notified: true };

      case 'WARNING_OVERLAY':
        await this.sendWarningOverlay(deviceId, overdueDays);
        return { locked: false, notified: true };

      case 'OVERDUE_ALERT':
        await this.sendOverdueAlert(deviceId, overdueDays);
        return { locked: false, notified: true };

      case 'APPLY_REMINDER':
        await this.applyLock(deviceId, imei, LOCK_LEVELS.REMINDER_MODE, 'auto_lock_reminder');
        return { locked: true, notified: false };

      case 'APPLY_PARTIAL':
        await this.applyLock(deviceId, imei, LOCK_LEVELS.PARTIAL_LOCK, 'auto_lock_partial');
        return { locked: true, notified: false };

      case 'APPLY_FULL':
        await this.applyLock(deviceId, imei, LOCK_LEVELS.FULL_LOCK, 'auto_lock_full');
        return { locked: true, notified: false };

      case 'APPLY_FULL_ADMIN_FLAG':
        await this.applyLock(deviceId, imei, LOCK_LEVELS.FULL_LOCK, 'auto_lock_full_admin_review');
        await this.flagForAdminReview(deviceId, overdueDays);
        return { locked: true, notified: false };

      default:
        return { locked: false, notified: false };
    }
  }

  getScheduleAction(overdueDays) {
    if (overdueDays >= -7 && overdueDays < -3) return { action: 'REMINDER_PUSH', level: LOCK_LEVELS.NONE };
    if (overdueDays >= -3 && overdueDays < 0) return { action: 'WARNING_OVERLAY', level: LOCK_LEVELS.NONE };
    if (overdueDays === 0) return { action: 'OVERDUE_ALERT', level: LOCK_LEVELS.NONE };
    if (overdueDays >= 1 && overdueDays < 3) return { action: 'APPLY_REMINDER', level: LOCK_LEVELS.REMINDER_MODE };
    if (overdueDays >= 3 && overdueDays < 7) return { action: 'APPLY_PARTIAL', level: LOCK_LEVELS.PARTIAL_LOCK };
    if (overdueDays >= 7 && overdueDays < 14) return { action: 'APPLY_FULL', level: LOCK_LEVELS.FULL_LOCK };
    if (overdueDays >= 14) return { action: 'APPLY_FULL_ADMIN_FLAG', level: LOCK_LEVELS.FULL_LOCK };
    return null;
  }

  async sendReminderNotification(deviceId, overdueDays) {
    await lockDeliveryService.deliverNotification(
      deviceId,
      'EMI_REMINDER',
      'EMI Payment Reminder',
      `Your EMI payment is due in ${Math.abs(overdueDays)} days. Please make your payment on time.`
    );
  }

  async sendWarningOverlay(deviceId, overdueDays) {
    await lockDeliveryService.deliverOverlayCommand(
      deviceId,
      'EMI_WARNING',
      'EMI Payment Warning',
      `Your EMI payment is due in ${Math.abs(overdueDays)} days. Failure to pay may result in device restrictions.`
    );
  }

  async sendOverdueAlert(deviceId, overdueDays) {
    await lockDeliveryService.deliverOverlayCommand(
      deviceId,
      'EMI_OVERDUE',
      'EMI Payment Overdue',
      'Your EMI payment is due today. Please pay immediately to avoid device lock.'
    );
  }

  async applyLock(deviceId, imei, lockLevel, reason) {
    const command = await lockCommandService.generateSignedCommand({
      deviceImei: imei,
      actionType: 'AUTO_LOCK',
      lockLevel,
      metadata: { reason, source: 'scheduler' },
    });

    await lockDeliveryService.deliverCommand(deviceId, command, lockLevel);

    await db.query(
      `UPDATE devices SET lock_level = $1, lock_reason = $2, locked_at = NOW(), updated_at = NOW() WHERE id = $3`,
      [lockLevel, reason, deviceId]
    );

    try {
      const sseService = require('../sse/sseService');
      sseService.emitDeviceLocked({ id: deviceId, imei, device_name: device.amapi_device_name, lock_level: lockLevel, lock_reason: reason, dealer_id: device.dealer_id });
    } catch (_) {}

    logger.info('Auto-lock applied', { deviceId, lockLevel, reason });
  }

  async flagForAdminReview(deviceId, overdueDays) {
    await db.query(
      `INSERT INTO admin_escalations (entity_type, entity_id, reason, note, status, created_at)
       VALUES ('device', $1, 'AUTO_LOCK_EXTENDED_OVERDUE', $2, 'pending', NOW())`,
      [deviceId, `Device overdue by ${overdueDays} days — requires admin review`]
    );

    logger.warn('Device flagged for admin review', { deviceId, overdueDays });
  }

  // Runs every 5 minutes. Finds devices whose dealer-issued grace period has expired
  // and sends a re-lock command via FCM. Clears grace_expires_at after re-locking.
  async runGraceExpiryCheck() {
    try {
      const expired = await db.query(
        `SELECT id, fcm_token, model, brand
         FROM devices
         WHERE grace_expires_at IS NOT NULL
           AND grace_expires_at < NOW()
           AND status NOT IN ('decoupled', 'disabled')`
      );

      if (!expired.rows.length) return;

      logger.info(`Grace expiry check: ${expired.rows.length} device(s) to re-lock`);

      for (const device of expired.rows) {
        try {
          // Send FCM re-lock command
          try {
            await lockCommandService.sendLockCommand(device.id, {
              reason:     'GRACE_EXPIRED',
              lock_level: 'FULL_LOCK',
            });
          } catch (_) {}

          // Clear grace_expires_at and update status
          await db.query(
            `UPDATE devices
             SET grace_expires_at = NULL,
                 status           = 'locked',
                 updated_at       = NOW()
             WHERE id = $1`,
            [device.id]
          );

          // Audit log
          await db.query(
            `INSERT INTO audit_log (actor, action, device_id, metadata, result, created_at)
             VALUES ('system', 'GRACE_EXPIRED_AUTO_RELOCK', $1, $2, 'success', NOW())`,
            [device.id, JSON.stringify({ model: device.model, brand: device.brand })]
          );

          logger.info('Grace expired — device re-locked', { deviceId: device.id });
        } catch (err) {
          logger.error('Grace expiry re-lock failed', { deviceId: device.id, error: err.message });
        }
      }
    } catch (err) {
      logger.error('Grace expiry check run failed', { error: err.message });
    }
  }
}

module.exports = new LockSchedulerService();
