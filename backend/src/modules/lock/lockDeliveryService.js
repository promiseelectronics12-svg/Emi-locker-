const amapiService = require('../devices/amapiService');
const { getMessaging } = require('../notifications/fcm.service');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const { LOCK_LEVELS } = require('./lockVerificationService');
const { insertDeliveryLog, getDeviceDeliveryInfo } = require('./lockDeliveryRepository');

let _pautService = null;
function getPautService() {
  if (!_pautService) _pautService = require('./pautService');
  return _pautService;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

class LockDeliveryService {
  buildFcmData(data) {
    return Object.fromEntries(
      Object.entries(data)
        .filter(([, value]) => value !== undefined && value !== null)
        .map(([key, value]) => [key, String(value)])
    );
  }

  async withRetry(operation, maxRetries = 3, baseDelay = 1000) {
    let attempt = 0;
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (error) {
        attempt++;
        if (attempt >= maxRetries) {
          throw error;
        }
        const delay = baseDelay * 2 ** (attempt - 1);
        logger.warn(`Delivery attempt ${attempt} failed, retrying in ${delay}ms...`, {
          error: error.message
        });
        await sleep(delay);
      }
    }
  }

  async deliverCommand(deviceId, command, lockLevel) {
    const results = {
      fcm: { attempted: false, success: false, error: null },
      amapi: { attempted: false, success: false, error: null },
      paut: { attempted: false, success: false, error: null }
    };

    const deviceRow = await getDeviceDeliveryInfo(deviceId);
    if (!deviceRow) {
      throw new Error('Device not found for delivery');
    }
    const { fcm_token, amapi_device_name, imei } = deviceRow;

    results.fcm = await this.deliverViaFcm(deviceId, fcm_token, command, lockLevel);

    results.amapi = await this.deliverViaAmapi(deviceId, amapi_device_name, lockLevel);

    if (lockLevel !== LOCK_LEVELS.FULL_LOCK) {
      results.paut = await this.deliverPaut(deviceId, imei, lockLevel);
    } else {
      results.paut = {
        attempted: false,
        success: false,
        error: null,
        channel: 'PAUT',
        skipped: true
      };
    }

    const anySuccess = results.fcm.success || results.amapi.success || results.paut.success;

    await this.logDeliveryResult(deviceId, command, results);

    return { delivered: anySuccess, results };
  }

  async deliverViaFcm(deviceId, fcmToken, command, lockLevel) {
    const result = { attempted: true, success: false, error: null, channel: 'FCM' };

    if (!fcmToken) {
      result.error = 'No FCM token registered for device';
      return result;
    }

    try {
      const appCommand = this.toAppCommand(command.actionType, lockLevel);
      const message = {
        token: fcmToken,
        data: this.buildFcmData({
          type: 'LOCK_COMMAND',
          command: appCommand,
          commandType: command.actionType,
          lockLevel: lockLevel || 'FULL_LOCK',
          nonce: command.nonce,
          timestamp: String(command.timestamp),
          expiresAt: command.expiresAt,
          hmacSignature: command.hmacSignature,
          deviceImei: command.deviceImei
        }),
        android: {
          priority: 'high',
          ttl: 5 * 60 * 1000
        }
      };

      await this.withRetry(() => getMessaging().send(message));
      result.success = true;
      logger.info('FCM lock command delivered', { deviceId });
    } catch (error) {
      result.error = error.message;
      logger.error('FCM delivery failed after 3 attempts', { deviceId, error: error.message });
    }

    return result;
  }

  toAppCommand(actionType, lockLevel) {
    if (actionType === 'UNLOCK' || lockLevel === LOCK_LEVELS.NONE) {
      return 'UNLOCK';
    }
    if (lockLevel === LOCK_LEVELS.PARTIAL_LOCK || lockLevel === LOCK_LEVELS.REMINDER_MODE) {
      return 'PARTIAL_LOCK';
    }
    return 'LOCK';
  }

  async deliverViaAmapi(deviceId, amapiDeviceName, lockLevel) {
    const result = { attempted: true, success: false, error: null, channel: 'AMAPI' };

    if (!amapiDeviceName) {
      result.error = 'No AMAPI device name registered';
      return result;
    }

    try {
      await amapiService.initialize();
      const enterpriseId = process.env.AMAPI_ENTERPRISE_ID;

      const policyMap = {
        REMINDER_MODE: this.buildReminderModePolicy(),
        PARTIAL_LOCK: this.buildPartialLockPolicy(),
        FULL_LOCK: this.buildFullLockPolicy()
      };

      const policy = policyMap[lockLevel] || policyMap.FULL_LOCK;

      await this.withRetry(() =>
        amapiService.setDevicePolicy(enterpriseId, amapiDeviceName, policy)
      );
      result.success = true;
      logger.info('AMAPI policy applied', { deviceId, lockLevel });
    } catch (error) {
      result.error = error.message;
      logger.error('AMAPI delivery failed after 3 attempts', { deviceId, error: error.message });
    }

    return result;
  }

  async deliverPaut(deviceId, imei, lockLevel) {
    const result = { attempted: true, success: false, error: null, channel: 'PAUT' };

    if (!imei) {
      result.error = 'No IMEI registered for device';
      return result;
    }

    try {
      const paut = await getPautService().issueToken({ deviceId, imei, lockLevel });
      result.success = true;
      result.tokenId = paut.jti;
      logger.info('PAUT issued for offline unlock', { deviceId, expiresAt: paut.expiresAt });
    } catch (error) {
      result.error = error.message;
      logger.error('PAUT issuance failed', { deviceId, error: error.message });
    }

    return result;
  }

  buildReminderModePolicy() {
    return {
      statusBarSettings: { disabled: false },
      statusBarNotifications: [
        {
          title: 'EMI Payment Reminder',
          text: 'Your EMI payment is overdue. Please make a payment to avoid device restrictions.',
          userCanDismiss: false
        }
      ]
    };
  }

  buildPartialLockPolicy() {
    // Read blocked apps from env for configurability (white-labeling support)
    const blockedApps = (
      process.env.PARTIAL_LOCK_BLOCKED_APPS ||
      'com.android.chrome,com.google.android.youtube,com.instagram.android,com.facebook.katana,com.whatsapp'
    )
      .split(',')
      .map((pkg) => ({ packageName: pkg.trim() }));

    return {
      installAppsDisabled: true,
      uninstallAppsDisabled: true,
      statusBarSettings: { disabled: true },
      statusBarNotifications: [
        {
          title: 'EMI Payment Required',
          text: 'Your device is partially locked due to overdue EMI. Contact your dealer.',
          userCanDismiss: false
        }
      ],
      disabledApplications: blockedApps
    };
  }

  buildFullLockPolicy() {
    // NOTE: Do NOT use preferredActivities with hardcoded com.android.launcher —
    // this crashes on MIUI, ColorOS, FuntouchOS, and other OEM ROMs.
    // Kiosk enforcement is handled by the EMI app itself via lockTask mode (FCM command).
    // AMAPI is used here only to enforce device-level restrictions.
    const lockTaskPackages = (process.env.FULL_LOCK_KIOSK_PACKAGES || 'com.emilocker.user')
      .split(',')
      .map((pkg) => pkg.trim());

    return {
      statusBarSettings: { disabled: true },
      statusBarNotifications: [
        {
          title: 'Device Locked — EMI Overdue',
          text: 'This device is locked due to non-payment. Contact your dealer to resolve.',
          userCanDismiss: false
        }
      ],
      installAppsDisabled: true,
      uninstallAppsDisabled: true,
      usbDataAccessDisabled: true,
      screenCaptureDisabled: true,
      adjustVolumeDisabled: true,
      factoryResetDisabled: true,
      factoryResetProtection: true,
      kioskCustomization: {
        powerButtonActions: 'POWER_BUTTON_AVAILABLE',
        systemErrorWarnings: 'ERROR_AND_WARNINGS_DISABLED',
        systemNavigation: 'NAVIGATION_DISABLED',
        statusBar: 'NOTIFICATIONS_AND_SYSTEM_INFO_DISABLED'
      },
      lockTaskPolicy: {
        packages: lockTaskPackages
      },
      wipeOnFailureEnabled: false
    };
  }

  async logDeliveryResult(deviceId, command, results) {
    try {
      await insertDeliveryLog({
        deviceId,
        commandNonce: command.nonce,
        commandType: command.actionType,
        fcmResult: results.fcm,
        amapiResult: results.amapi,
        pautResult: results.paut
      });
    } catch (error) {
      logger.error('Failed to log delivery result', { deviceId, error: error.message });
    }
  }

  async deliverNotification(deviceId, type, title, body) {
    const device = await db.query(`SELECT fcm_token FROM devices WHERE id = $1`, [deviceId]);

    if (device.rows.length === 0 || !device.rows[0].fcm_token) {
      return { success: false, error: 'No FCM token' };
    }

    try {
      await getMessaging().send({
        token: device.rows[0].fcm_token,
        data: this.buildFcmData({
          type,
          title,
          body
        }),
        android: { priority: 'high' }
      });
      return { success: true };
    } catch (error) {
      logger.error('Notification delivery failed', { deviceId, error: error.message });
      return { success: false, error: error.message };
    }
  }

  async deliverOverlayCommand(deviceId, type, title, body) {
    const device = await db.query(`SELECT fcm_token FROM devices WHERE id = $1`, [deviceId]);

    if (device.rows.length === 0 || !device.rows[0].fcm_token) {
      return { success: false, error: 'No FCM token' };
    }

    try {
      await getMessaging().send({
        token: device.rows[0].fcm_token,
        data: this.buildFcmData({
          type,
          title,
          body,
          overlay: 'true',
          dismissible: 'false'
        }),
        android: { priority: 'high' }
      });
      return { success: true };
    } catch (error) {
      logger.error('Overlay delivery failed', { deviceId, error: error.message });
      return { success: false, error: error.message };
    }
  }
}

module.exports = new LockDeliveryService();
