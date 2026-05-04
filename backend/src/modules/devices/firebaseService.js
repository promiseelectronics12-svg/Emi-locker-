const admin = require('firebase-admin');
const logger = require('../../utils/logger');

class FirebaseService {
  constructor() {
    this.db = null;
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    try {
      const serviceAccount = {
        type: 'service_account',
        project_id: process.env.FIREBASE_PROJECT_ID,
        private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
        private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        client_email: process.env.FIREBASE_CLIENT_EMAIL,
        client_id: process.env.FIREBASE_CLIENT_ID,
        auth_uri: 'https://accounts.google.com/o/oauth2/auth',
        token_uri: 'https://oauth2.googleapis.com/token',
        auth_provider_x509_cert_url: 'https://www.googleapis.com/oauth2/v1/certs',
        client_x509_cert_url: process.env.FIREBASE_CLIENT_CERT_URL
      };

      if (!admin.apps.length) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          databaseURL: process.env.FIREBASE_DATABASE_URL
        });
      }

      this.db = admin.database();
      this.initialized = true;
      logger.info('Firebase service initialized successfully');
    } catch (error) {
      logger.error('Failed to initialize Firebase service:', error);
      throw error;
    }
  }

  async ensureInitialized() {
    if (!this.initialized) {
      await this.initialize();
    }
  }

  async writeDeviceStatus(deviceId, status) {
    await this.ensureInitialized();

    const timestamp = Date.now();
    const statusData = {
      ...status,
      lastUpdated: timestamp,
      updatedAt: new Date().toISOString()
    };

    const updates = {};
    updates[`/devices/${deviceId}/status`] = statusData;
    updates[`/devices/${deviceId}/lastUpdated`] = timestamp;

    await this.db.ref().update(updates);
    logger.info(`Device status written to Firebase RTDB: ${deviceId}`, { status: statusData });

    return statusData;
  }

  async getDeviceStatus(deviceId) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/status`).once('value');
    const status = snapshot.val();

    if (!status) {
      return null;
    }

    return {
      ...status,
      lastUpdated: status.lastUpdated || snapshot.child('lastUpdated').val()
    };
  }

  async getDeviceLockState(deviceId) {
    const status = await this.getDeviceStatus(deviceId);

    if (!status) {
      return {
        isLocked: null,
        lockState: 'unknown',
        lastUpdated: null
      };
    }

    return {
      isLocked: status.lockState === 'locked',
      lockState: status.lockState || 'unknown',
      lockReason: status.lockReason || null,
      lastUpdated: status.lastUpdated
    };
  }

  async updateLockState(deviceId, lockState, metadata = {}) {
    const timestamp = Date.now();

    const updates = {};
    updates[`/devices/${deviceId}/status/lockState`] = lockState;
    updates[`/devices/${deviceId}/status/lockReason`] = metadata.reason || null;
    updates[`/devices/${deviceId}/status/lockedBy`] = metadata.lockedBy || null;
    updates[`/devices/${deviceId}/status/lastUpdated`] = timestamp;
    updates[`/devices/${deviceId}/status/updatedAt`] = new Date().toISOString();

    if (metadata.unlockCode) {
      updates[`/devices/${deviceId}/status/unlockCode`] = metadata.unlockCode;
    }

    await this.db.ref().update(updates);
    logger.info(`Lock state updated in Firebase RTDB: ${deviceId} -> ${lockState}`);

    return this.getDeviceLockState(deviceId);
  }

  async writeDeviceMetadata(deviceId, metadata) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/metadata`] = {
      ...metadata,
      lastUpdated: Date.now(),
      updatedAt: new Date().toISOString()
    };

    await this.db.ref().update(updates);
    logger.info(`Device metadata written to Firebase RTDB: ${deviceId}`);

    return updates[`/devices/${deviceId}/metadata`];
  }

  async getDeviceMetadata(deviceId) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/metadata`).once('value');
    return snapshot.val();
  }

  async writeEnrollmentData(deviceId, enrollmentData) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/enrollment`] = {
      ...enrollmentData,
      enrolledAt: Date.now(),
      enrolledAtISO: new Date().toISOString()
    };

    await this.db.ref().update(updates);
    logger.info(`Enrollment data written to Firebase RTDB: ${deviceId}`);

    return updates[`/devices/${deviceId}/enrollment`];
  }

  async getEnrollmentData(deviceId) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/enrollment`).once('value');
    return snapshot.val();
  }

  async writeCommandHistory(deviceId, command) {
    await this.ensureInitialized();

    const commandRef = this.db.ref(`/devices/${deviceId}/commandHistory`).push();
    await commandRef.set({
      ...command,
      timestamp: Date.now(),
      createdAt: new Date().toISOString()
    });

    const recentHistorySnapshot = await this.db.ref(`/devices/${deviceId}/commandHistory`).orderByChild('timestamp').limitToLast(50).once('value');
    const recentHistory = recentHistorySnapshot.val() || {};
    const keys = Object.keys(recentHistory);

    if (keys.length > 50) {
      const oldestKeys = keys.slice(0, keys.length - 50);
      const deletes = {};
      oldestKeys.forEach(key => {
        deletes[`/devices/${deviceId}/commandHistory/${key}`] = null;
      });
      await this.db.ref().update(deletes);
    }

    return commandRef.key;
  }

  async getCommandHistory(deviceId, limit = 50) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/commandHistory`)
      .orderByChild('timestamp')
      .limitToLast(limit)
      .once('value');

    const history = snapshot.val() || {};
    return Object.values(history).reverse();
  }

  async deleteDeviceData(deviceId) {
    await this.ensureInitialized();

    await this.db.ref(`/devices/${deviceId}`).remove();
    logger.info(`All device data removed from Firebase RTDB: ${deviceId}`);
  }

  async subscribeToDeviceStatus(deviceId, callback) {
    await this.ensureInitialized();

    const ref = this.db.ref(`/devices/${deviceId}/status`);
    const listener = ref.on('value', (snapshot) => {
      callback(snapshot.val());
    });

    return () => {
      ref.off('value', listener);
    };
  }

  async setDeviceOnline(deviceId, isOnline) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/status/isOnline`] = isOnline;
    updates[`/devices/${deviceId}/status/lastSeen`] = Date.now();
    updates[`/devices/${deviceId}/status/onlineAt`] = isOnline ? new Date().toISOString() : null;

    await this.db.ref().update(updates);
    logger.info(`Device online status set in Firebase RTDB: ${deviceId} -> ${isOnline}`);
  }

  async writePolicyStatus(deviceId, policyData) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/policy`] = {
      ...policyData,
      lastUpdated: Date.now(),
      updatedAt: new Date().toISOString()
    };

    await this.db.ref().update(updates);
    logger.info(`Policy status written to Firebase RTDB: ${deviceId}`);

    return updates[`/devices/${deviceId}/policy`];
  }

  async getPolicyStatus(deviceId) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/policy`).once('value');
    return snapshot.val();
  }

  async writeSignedCommand(deviceId, signedCommand) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/commands`] = signedCommand;

    await this.db.ref().update(updates);
    logger.info(`Signed command written to Firebase RTDB: ${deviceId}`);

    return signedCommand;
  }

  async getSignedCommand(deviceId) {
    await this.ensureInitialized();

    const snapshot = await this.db.ref(`/devices/${deviceId}/commands`).once('value');
    return snapshot.val();
  }

  async clearSignedCommand(deviceId) {
    await this.ensureInitialized();

    await this.db.ref(`/devices/${deviceId}/commands`).remove();
    logger.info(`Signed command cleared from Firebase RTDB: ${deviceId}`);
  }

  async sendPushToDevice(deviceId, notification) {
    await this.ensureInitialized();

    const deviceRef = this.db.ref(`/devices/${deviceId}`);

    try {
      const fcmTokenSnapshot = await deviceRef.child('fcmToken').once('value');
      const fcmToken = fcmTokenSnapshot.val();

      if (!fcmToken) {
        logger.warn(`No FCM token found for device: ${deviceId}`);
        return { success: false, reason: 'No FCM token' };
      }

      const message = {
        notification: {
          title: notification.title,
          body: notification.body
        },
        data: notification.data || {},
        token: fcmToken
      };

      const result = await admin.messaging().send(message);
      logger.info(`Push notification sent to device: ${deviceId}`, { messageId: result });
      return { success: true, messageId: result };
    } catch (error) {
      logger.error(`Failed to send push notification to device: ${deviceId}`, error);
      return { success: false, error: error.message };
    }
  }

  async writeDecouplingData(deviceId, decouplingData) {
    await this.ensureInitialized();

    const updates = {};
    updates[`/devices/${deviceId}/decoupling`] = {
      ...decouplingData,
      lastUpdated: Date.now(),
      updatedAt: new Date().toISOString()
    };

    await this.db.ref().update(updates);
    logger.info(`Decoupling data written to Firebase RTDB: ${deviceId}`);

    return updates[`/devices/${deviceId}/decoupling`];
  }
}

module.exports = new FirebaseService();
