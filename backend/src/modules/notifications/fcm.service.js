const admin = require('firebase-admin');

let firebaseApp = null;

function initializeFCM() {
  if (firebaseApp) {
    return firebaseApp;
  }

  if (admin.apps.length > 0) {
    firebaseApp = admin.app();
    return firebaseApp;
  }

  const serviceAccount = {
    projectId: process.env.FIREBASE_PROJECT_ID,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  };

  firebaseApp = admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });

  return firebaseApp;
}

function getMessaging() {
  const app = initializeFCM();
  return app.messaging();
}

async function sendToDevice(fcmToken, payload) {
  const messaging = getMessaging();

  const message = {
    token: fcmToken,
    notification: payload.title && payload.body
      ? { title: payload.title, body: payload.body }
      : undefined,
    data: Object.fromEntries(
      Object.entries(payload).map(([k, v]) => [k, String(v)])
    ),
    android: {
      priority: 'high',
      // Only set android.notification for actual notification messages.
      // Setting it on data-only messages prevents onMessageReceived from firing in background.
      ...(payload.title && payload.body ? {
        notification: {
          channelId: 'emi_locker_high_priority',
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      } : {}),
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: 1,
          mutableContent: 1,
        },
      },
    },
  };

  try {
    const response = await messaging.send(message);
    return { messageId: response, success: true };
  } catch (error) {
    const err = error;
    console.error('FCM send error:', { code: err.code, message: err.message });
    const invalidToken = [
      'messaging/registration-token-not-registered',
      'messaging/invalid-registration-token',
      'messaging/invalid-argument',
    ].includes(err.code);
    return {
      messageId: '',
      success: false,
      code: err.code || '',
      error: err.message || 'FCM send failed',
      invalidToken,
    };
  }
}

async function sendMulticast(tokens, payload) {
  const messaging = getMessaging();

  const message = {
    tokens,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data,
    android: {
      priority: 'high',
      notification: {
        channelId: 'emi_locker_high_priority',
      },
    },
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    return {
      successCount: response.successCount,
      failureCount: response.failureCount,
      errors: response.responses
        .filter(r => !r.success)
        .map(r => r.error),
    };
  } catch (error) {
    const err = error;
    console.error('FCM multicast error:', { code: err.code, message: err.message });
    throw error;
  }
}

function buildLockCommandPayload(
  deviceId,
  lockLevel,
  signature,
  nonce,
  imei,
  serial,
  soc_model
) {
  return {
    type: 'LOCK_COMMAND',
    command: lockLevel >= 7 ? 'FULL_LOCK' : lockLevel >= 3 ? 'PARTIAL_LOCK' : 'LOCK',
    lockLevel,
    timestamp: new Date().toISOString(),
    signature,
    nonce,
    imei,
    serial,
    soc_model,
    serverId: process.env.SERVER_ID || 'server-001',
  };
}

function buildUnlockCommandPayload(
  deviceId,
  signature,
  expiryHours = 48,
  nonce,
  imei,
  serial,
  soc_model
) {
  const now = new Date();
  const expiry = new Date(now.getTime() + expiryHours * 60 * 60 * 1000);

  return {
    type: 'UNLOCK_COMMAND',
    command: 'UNLOCK',
    timestamp: now.toISOString(),
    expiry: expiry.toISOString(),
    signature,
    nonce,
    imei,
    serial,
    soc_model,
    serverId: process.env.SERVER_ID || 'server-001',
  };
}

function buildReminderPayload(daysUntilDue, amountDue, dueDate, dealerContact) {
  return {
    type: 'PAYMENT_REMINDER',
    title: 'Payment Reminder',
    body: `Payment of ${amountDue} due in ${daysUntilDue} days`,
    daysUntilDue,
    amountDue,
    dueDate,
    dealerContact,
    clickAction: 'EMI_PAYMENT',
  };
}

function buildDealerMessagePayload(message, dealerId, dealerName) {
  return {
    type: 'DEALER_MESSAGE',
    command: 'MESSAGE',
    message,
    dealerId,
    dealerName,
    timestamp: new Date().toISOString(),
    priority: 'high',
  };
}

module.exports = {
  initializeFCM,
  getMessaging,
  sendToDevice,
  sendMulticast,
  buildLockCommandPayload,
  buildUnlockCommandPayload,
  buildReminderPayload,
  buildDealerMessagePayload,
};
