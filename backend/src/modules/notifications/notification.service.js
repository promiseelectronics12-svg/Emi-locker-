const {
  sendToDevice,
  buildLockCommandPayload,
  buildUnlockCommandPayload,
  buildReminderPayload,
  buildDealerMessagePayload,
} = require('./fcm.service');
const {
  sendLockConfirmationSMS,
  sendUnlockConfirmationSMS,
  sendCriticalAlertSMS,
} = require('./sms.service');
const {
  checkAndIncrementDealerMessageRateLimit,
  getDealerMessageStats,
} = require('./dealer-message-rate-limiter');
const {
  createNotificationRecord,
  updateNotificationStatus,
} = require('./notification.repository');
const { getDeviceById } = require('../devices/device.repository');

function sanitizeMessage(message) {
  return message
    .replace(/<[^>]*>/g, '')
    .replace(/[^\w\s\-.,!?;:()@]/g, '')
    .slice(0, 500);
}

async function sendLockCommand(deviceId, lockLevel) {
  try {
    const device = await getDeviceById(deviceId);
    if (!device) {
      return { success: false, error: 'Device not found' };
    }

    if (!device.fcm_token) {
      return { success: false, error: 'Device has no FCM token' };
    }

    const { createSignedLockCommand } = require('../keys/hmac.service');
    const signedCommand = createSignedLockCommand(
      deviceId,
      lockLevel,
      device.imei,
      device.serial,
      device.soc_model
    );

    const payload = buildLockCommandPayload(
      deviceId,
      lockLevel,
      signedCommand.signature,
      signedCommand.nonce,
      signedCommand.imei,
      signedCommand.serial,
      signedCommand.soc_model
    );

    let fcmResult;
    try {
      fcmResult = await sendToDevice(device.fcm_token, payload);
    } catch (error) {
      console.error('FCM send failed:', error);
      fcmResult = { messageId: '', success: false };
    }

    if (!fcmResult.success) {
      const smsResult = await sendLockConfirmationSMS(
        device.phone,
        deviceId,
        lockLevel >= 7 ? 'FULL_LOCK' : lockLevel >= 3 ? 'PARTIAL_LOCK' : 'LOCK'
      );

      if (smsResult.success) {
        const notificationId = await createNotificationRecord({
          device_id: deviceId,
          type: 'LOCK_COMMAND',
          payload: payload,
          status: 'SENT',
          fcm_message_id: fcmResult.messageId || undefined,
          provider: 'TWILIO',
        });
        return {
          success: true,
          notificationId,
          smsMessageId: smsResult.messageId,
          fallbackUsed: 'SMS',
        };
      }

      const notificationId = await createNotificationRecord({
        device_id: deviceId,
        type: 'LOCK_COMMAND',
        payload: payload,
        status: 'FAILED',
        fcm_message_id: fcmResult.messageId || undefined,
        provider: 'FCM',
      });
      return {
        success: false,
        notificationId,
        error: 'FCM and SMS both failed',
      };
    }

    const notificationId = await createNotificationRecord({
      device_id: deviceId,
      type: 'LOCK_COMMAND',
      payload: payload,
      status: 'SENT',
      fcm_message_id: fcmResult.messageId,
      provider: 'FCM',
    });

    return {
      success: true,
      notificationId,
      fcmMessageId: fcmResult.messageId,
    };
  } catch (error) {
    console.error('sendLockCommand error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

async function sendUnlockCommand(deviceId, expiryHours = 48) {
  try {
    const device = await getDeviceById(deviceId);
    if (!device) {
      return { success: false, error: 'Device not found' };
    }

    if (!device.fcm_token) {
      return { success: false, error: 'Device has no FCM token' };
    }

    const { createSignedUnlockCommand } = require('../keys/hmac.service');
    const signedCommand = createSignedUnlockCommand(
      deviceId,
      expiryHours,
      device.imei,
      device.serial,
      device.soc_model
    );

    const payload = buildUnlockCommandPayload(
      deviceId,
      signedCommand.signature,
      expiryHours,
      signedCommand.nonce,
      signedCommand.imei,
      signedCommand.serial,
      signedCommand.soc_model
    );

    let fcmResult;
    try {
      fcmResult = await sendToDevice(device.fcm_token, payload);
    } catch (error) {
      console.error('FCM send failed:', error);
      fcmResult = { messageId: '', success: false };
    }

    if (!fcmResult.success) {
      const smsResult = await sendUnlockConfirmationSMS(device.phone, deviceId);

      if (smsResult.success) {
        const notificationId = await createNotificationRecord({
          device_id: deviceId,
          type: 'UNLOCK_COMMAND',
          payload: payload,
          status: 'SENT',
          fcm_message_id: fcmResult.messageId || undefined,
          provider: 'TWILIO',
        });
        return {
          success: true,
          notificationId,
          smsMessageId: smsResult.messageId,
          fallbackUsed: 'SMS',
        };
      }

      const notificationId = await createNotificationRecord({
        device_id: deviceId,
        type: 'UNLOCK_COMMAND',
        payload: payload,
        status: 'FAILED',
        fcm_message_id: fcmResult.messageId || undefined,
        provider: 'FCM',
      });
      return {
        success: false,
        notificationId,
        error: 'FCM and SMS both failed',
      };
    }

    const notificationId = await createNotificationRecord({
      device_id: deviceId,
      type: 'UNLOCK_COMMAND',
      payload: payload,
      status: 'SENT',
      fcm_message_id: fcmResult.messageId,
      provider: 'FCM',
    });

    return {
      success: true,
      notificationId,
      fcmMessageId: fcmResult.messageId,
    };
  } catch (error) {
    console.error('sendUnlockCommand error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

async function sendReminderNotification(deviceId, daysUntilDue, amountDue, dueDate) {
  try {
    const device = await getDeviceById(deviceId);
    if (!device) {
      return { success: false, error: 'Device not found' };
    }

    if (!device.fcm_token) {
      return { success: false, error: 'Device has no FCM token' };
    }

    const payload = buildReminderPayload(
      daysUntilDue,
      amountDue || 0,
      dueDate || new Date().toISOString(),
      device.dealer_phone || 'Contact your dealer'
    );

    const fcmResult = await sendToDevice(device.fcm_token, payload);

    const notificationId = await createNotificationRecord({
      device_id: deviceId,
      type: 'PAYMENT_REMINDER',
      title: payload.title,
      body: payload.body,
      payload: payload,
      status: fcmResult.success ? 'SENT' : 'FAILED',
      fcm_message_id: fcmResult.messageId,
      provider: 'FCM',
    });

    return {
      success: fcmResult.success,
      notificationId,
      fcmMessageId: fcmResult.messageId,
    };
  } catch (error) {
    console.error('sendReminderNotification error:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

async function sendDealerMessage(deviceId, message, dealerId, dealerName, isAdmin = false) {
  try {
    const device = await getDeviceById(deviceId);
    if (!device) {
      return {
        success: false,
        rateLimit: { allowed: true, currentCount: 0, limit: 10, resetAt: new Date() },
        error: 'Device not found'
      };
    }

    if (!isAdmin && device.dealer_id !== dealerId) {
      return {
        success: false,
        rateLimit: { allowed: true, currentCount: 0, limit: 10, resetAt: new Date() },
        error: 'Unauthorized: dealer does not have access to this device'
      };
    }

    const rateLimitCheck = await checkAndIncrementDealerMessageRateLimit(deviceId);

    if (!rateLimitCheck.allowed) {
      return {
        success: false,
        rateLimit: rateLimitCheck,
        error: `Daily message limit reached. Limit: ${rateLimitCheck.limit} messages per day.`,
      };
    }

    if (!device.fcm_token) {
      return { success: false, rateLimit: rateLimitCheck, error: 'Device has no FCM token' };
    }

    const sanitizedMessage = sanitizeMessage(message);
    if (sanitizedMessage.length === 0) {
      return { success: false, rateLimit: rateLimitCheck, error: 'Message contains no valid characters' };
    }

    const payload = buildDealerMessagePayload(sanitizedMessage, dealerId, dealerName);
    const fcmResult = await sendToDevice(device.fcm_token, payload);

    if (!fcmResult.success) {
      return {
        success: false,
        rateLimit: rateLimitCheck,
        error: 'FCM send failed',
      };
    }

    const notificationId = await createNotificationRecord({
      device_id: deviceId,
      type: 'DEALER_MESSAGE',
      title: 'Message from Dealer',
      body: message,
      payload: payload,
      status: 'SENT',
      fcm_message_id: fcmResult.messageId,
      provider: 'FCM',
    });

    return {
      success: true,
      notificationId,
      rateLimit: rateLimitCheck,
    };
  } catch (error) {
    console.error('sendDealerMessage error:', error);
    return {
      success: false,
      rateLimit: { allowed: true, currentCount: 0, limit: 10, resetAt: new Date() },
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

async function getDeviceMessageStats(deviceId) {
  return getDealerMessageStats(deviceId);
}

async function markNotificationDelivered(notificationId, fcmMessageId) {
  await updateNotificationStatus(notificationId, 'DELIVERED', {
    fcm_message_id: fcmMessageId,
    delivered_at: new Date(),
  });
}

async function markNotificationFailed(notificationId, reason) {
  await updateNotificationStatus(notificationId, 'FAILED', {
    failed_at: new Date(),
    failure_reason: reason,
  });
}

module.exports = {
  sendLockCommand,
  sendUnlockCommand,
  sendReminderNotification,
  sendDealerMessage,
  getDeviceMessageStats,
  markNotificationDelivered,
  markNotificationFailed,
};
