const { initializeFCM, getMessaging, sendToDevice, sendMulticast } = require('./fcm.service');
const {
  sendLockCommand,
  sendUnlockCommand,
  sendReminderNotification,
  sendDealerMessage,
  getDeviceMessageStats,
  markNotificationDelivered,
  markNotificationFailed,
} = require('./notification.service');
const { sendSMS, sendLockConfirmationSMS, sendUnlockConfirmationSMS, sendCriticalAlertSMS } = require('./sms.service');
const {
  checkDealerMessageRateLimit,
  incrementDealerMessageCount,
  getDealerMessageStats,
} = require('./dealer-message-rate-limiter');
const {
  createNotificationRecord,
  updateNotificationStatus,
  findNotificationsByDevice,
  findPendingNotifications,
  getNotificationStatsByDevice,
} = require('./notification.repository');
const notificationRoutes = require('./notification.routes');

module.exports = {
  initializeFCM,
  getMessaging,
  sendToDevice,
  sendMulticast,
  sendLockCommand,
  sendUnlockCommand,
  sendReminderNotification,
  sendDealerMessage,
  getDeviceMessageStats,
  markNotificationDelivered,
  markNotificationFailed,
  sendSMS,
  sendLockConfirmationSMS,
  sendUnlockConfirmationSMS,
  sendCriticalAlertSMS,
  checkDealerMessageRateLimit,
  incrementDealerMessageCount,
  getDealerMessageStats,
  createNotificationRecord,
  updateNotificationStatus,
  findNotificationsByDevice,
  findPendingNotifications,
  getNotificationStatsByDevice,
  notificationRoutes,
};