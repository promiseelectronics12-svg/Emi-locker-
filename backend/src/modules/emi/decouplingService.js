const crypto = require('crypto');
const emiModel = require('./emiModel');
const firebaseService = require('../devices/firebaseService');
const amapiService = require('../devices/amapiService');
const logger = require('../../utils/logger');
const { sendPushNotification, sendAdminNotification } = require('../devices/firebaseService');

const DECOUPLING_STATES = {
  EMI_ACTIVE: 'EMI_ACTIVE',
  FINAL_PAYMENT_RECEIVED: 'FINAL_PAYMENT_RECEIVED',
  DEALER_NOTIFIED: 'DEALER_NOTIFIED',
  PENDING_ADMIN_DECOUPLE: 'PENDING_ADMIN_DECOUPLE',
  DEVICE_DECOUPLED: 'DEVICE_DECOUPLED'
};

const VALID_TRANSITIONS = {
  [DECOUPLING_STATES.EMI_ACTIVE]: [DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED],
  [DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED]: [DECOUPLING_STATES.DEALER_NOTIFIED, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE],
  [DECOUPLING_STATES.DEALER_NOTIFIED]: [DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE],
  [DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE]: [DECOUPLING_STATES.DEVICE_DECOUPLED],
  [DECOUPLING_STATES.DEVICE_DECOUPLED]: []
};

const FRAUD_WINDOW_HOURS = 120;

class DecouplingService {
  constructor() {
    this.rtocSecret = process.env.RTOC_SIGNING_SECRET || 'default-rtoc-secret-change-me';
  }

  async handleFinalPayment(deviceId, paymentDetails) {
    const device = await emiModel.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    if (device.schedule_id) {
      const schedule = await emiModel.getScheduleByDeviceId(deviceId);
      const totalPaidResult = await require('../../config/database').query(
        `SELECT COALESCE(SUM(amount), 0) as total_paid FROM emi_payments WHERE emi_schedule_id = $1 AND status = 'completed'`,
        [device.schedule_id]
      );
      const totalPaid = parseFloat(totalPaidResult.rows[0].total_paid);

      if (totalPaid >= parseFloat(schedule.total_amount)) {
        return this.transitionToState(deviceId, DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED, {
          final_payment_id: paymentDetails.paymentId,
          final_payment_amount: paymentDetails.amount
        });
      }
    }

    return null;
  }

  async transitionToState(deviceId, newState, additionalData = {}) {
    const currentState = await emiModel.getDecouplingState(deviceId);

    if (!currentState) {
      throw new Error('No decoupling state found for device');
    }

    const validNextStates = VALID_TRANSITIONS[currentState.state] || [];
    if (!validNextStates.includes(newState)) {
      throw new Error(`Invalid state transition from ${currentState.state} to ${newState}`);
    }

    const stateHandlers = {
      [DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED]: async () => {
        await this.notifyDealer(deviceId);
      },
      [DECOUPLING_STATES.DEALER_NOTIFIED]: async () => {
        return this.startFraudDetectionWindow(deviceId);
      },
      [DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE]: async () => {
        await this.sendAdminNotification(deviceId);
      },
      [DECOUPLING_STATES.DEVICE_DECOUPLED]: async () => {
        await this.executeDecoupling(deviceId);
      }
    };

    if (stateHandlers[newState]) {
      await stateHandlers[newState]();
    }

    const updated = await emiModel.updateDecouplingState(deviceId, newState, additionalData);

    await this.logStateTransition(deviceId, currentState.state, newState, additionalData);

    return updated;
  }

  async notifyDealer(deviceId) {
    const device = await emiModel.getDeviceById(deviceId);

    const deviceData = await require('../../config/database').query(
      `SELECT d.*, dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM devices d
       JOIN dealers dl ON d.dealer_id = dl.id
       WHERE d.id = $1`,
      [deviceId]
    );

    const deviceInfo = deviceData.rows[0];

    await firebaseService.sendPushToDevice(deviceId, {
      title: 'EMI Complete - Final Payment Received',
      body: `Final payment of ${device.emi_amount} BDT received for device ${deviceInfo.device_name}. Decoupling process will begin.`,
      data: {
        type: 'DECOUPLING_INITIATED',
        deviceId,
        state: DECOUPLING_STATES.DEALER_NOTIFIED
      }
    });

    logger.info(`Dealer notified about final payment for device ${deviceId}`);

    return { notified: true, dealerId: deviceInfo.dealer_id };
  }

  async startFraudDetectionWindow(deviceId) {
    const result = await require('../../config/database').query(
      `UPDATE decoupling_state
       SET fraud_window_started_at = NOW(),
           fraud_window_ends_at = NOW() + INTERVAL '5 days',
           updated_at = NOW()
       WHERE device_id = $1
       RETURNING *`,
      [deviceId]
    );

    logger.info(`Fraud detection window started for device ${deviceId}`);

    return result.rows[0];
  }

  async checkFraudWindowExpired(deviceId) {
    const state = await emiModel.getDecouplingState(deviceId);

    if (!state || state.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      return false;
    }

    if (!state.fraud_window_ends_at) {
      return false;
    }

    const windowEnd = new Date(state.fraud_window_ends_at);
    const now = new Date();

    return now >= windowEnd;
  }

  async canAutoDecouple(deviceId) {
    const state = await emiModel.getDecouplingState(deviceId);

    if (!state) {
      return false;
    }

    if (state.fraud_flag) {
      return false;
    }

    if (state.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      return false;
    }

    return this.checkFraudWindowExpired(deviceId);
  }

  async flagFraud(deviceId, flaggedBy, reason = null) {
    const state = await emiModel.getDecouplingState(deviceId);

    if (!state) {
      throw new Error('No decoupling state found');
    }

    if (state.state !== DECOUPLING_STATES.DEALER_NOTIFIED && state.state !== DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE) {
      throw new Error('Cannot flag fraud in current state');
    }

    if (state.fraud_window_ends_at) {
      const windowEnd = new Date(state.fraud_window_ends_at);
      const now = new Date();
      if (now > windowEnd && state.state === DECOUPLING_STATES.DEALER_NOTIFIED) {
        throw new Error('Fraud window has expired');
      }
    }

    const updated = await emiModel.flagFraud(deviceId, flaggedBy, reason);

    await firebaseService.sendPushToDevice(deviceId, {
      title: 'Fraud Flag Raised',
      body: 'A fraud flag has been raised for this device. Admin review required.',
      data: {
        type: 'FRAUD_FLAG',
        deviceId,
        reason
      }
    });

    await sendAdminNotification({
      title: 'Fraud Flag Raised',
      body: `Fraud flag raised for device ${deviceId}. Manual review required before decoupling.`,
      data: { deviceId, type: 'FRAUD_FLAG' }
    });

    logger.warn(`Fraud flag raised for device ${deviceId} by ${flaggedBy}`, { reason });

    return updated;
  }

  async sendAdminNotification(deviceId) {
    const device = await emiModel.getDeviceById(deviceId);

    await sendAdminNotification({
      title: 'Decoupling Pending',
      body: `Device ${device.device_name} (${device.imei}) is ready for decoupling after 5-day window with no fraud flags.`,
      data: {
        deviceId,
        type: 'DECOUPLING_PENDING',
        scheduleId: device.schedule_id
      }
    });

    logger.info(`Admin notified about pending decoupling for device ${deviceId}`);
  }

  async executeDecoupling(deviceId) {
    const device = await emiModel.getDeviceById(deviceId);

    const rtocCode = this.generateRTOC(deviceId);

    await amapiService.initialize();

    try {
      await amapiService.deleteDevice(device.amapi_device_name);

      logger.info(`AMAPI device deleted for decoupling: ${deviceId}`);
    } catch (error) {
      logger.error(`Failed to delete AMAPI device for ${deviceId}:`, error);
      throw new Error('Failed to execute decoupling via AMAPI');
    }

    await firebaseService.writeDecouplingData(deviceId, {
      state: DECOUPLING_STATES.DEVICE_DECOUPLED,
      decoupledAt: new Date().toISOString(),
      rtocCode
    });

    await firebaseService.sendPushToDevice(deviceId, {
      title: 'Device Decoupled',
      body: 'Congratulations! Your device has been fully decoupled. All restrictions have been lifted.',
      data: {
        type: 'DEVICE_DECOUPLED',
        deviceId
      }
    });

    await this.cleanupDeviceData(deviceId);

    logger.info(`Device ${deviceId} fully decoupled. RTOC: ${rtocCode}`);

    return {
      success: true,
      deviceId,
      rtocCode,
      decoupledAt: new Date().toISOString()
    };
  }

  generateRTOC(deviceId) {
    const timestamp = Date.now().toString(36);
    const randomBytes = crypto.randomBytes(4).toString('hex');
    const payload = `${deviceId}:${timestamp}:${randomBytes}`;

    const hmac = crypto.createHmac('sha256', this.rtocSecret);
    hmac.update(payload);
    const signature = hmac.digest('hex').substring(0, 8);

    return `RTOC-${timestamp}-${randomBytes}-${signature}`.toUpperCase();
  }

  verifyRTOC(rtocCode, deviceId) {
    const parts = rtocCode.split('-');
    if (parts.length !== 4 || parts[0] !== 'RTOC') {
      return false;
    }

    const timestamp = parts[1];
    const randomBytes = parts[2];
    const providedSignature = parts[3];

    const payload = `${deviceId}:${timestamp}:${randomBytes}`;
    const hmac = crypto.createHmac('sha256', this.rtocSecret);
    hmac.update(payload);
    const expectedSignature = hmac.digest('hex').substring(0, 8);

    return crypto.timingSafeEqual(
      Buffer.from(providedSignature),
      Buffer.from(expectedSignature)
    );
  }

  async cleanupDeviceData(deviceId) {
    await require('../../config/database').query(
      `UPDATE devices
       SET status = 'decoupled',
           unlock_code_hash = NULL,
           unlock_code_salt = NULL,
           managed_google_account = NULL,
           updated_at = NOW()
       WHERE id = $1`,
      [deviceId]
    );

    await require('../../config/database').query(
      `UPDATE emi_schedules
       SET status = 'completed'
       WHERE device_id = $1`,
      [deviceId]
    );

    logger.info(`Device data cleaned up after decoupling: ${deviceId}`);
  }

  async initiateDecouplingFlow(deviceId, scheduleId) {
    const existing = await emiModel.getDecouplingState(deviceId);

    if (existing) {
      if (existing.state === DECOUPLING_STATES.DEVICE_DECOUPLED) {
        throw new Error('Device has already been decoupled');
      }
      return existing;
    }

    const decouplingState = await emiModel.createDecouplingState(deviceId, scheduleId);

    logger.info(`Decoupling flow initiated for device ${deviceId}`);

    return decouplingState;
  }

  async getDecouplingStatus(deviceId) {
    const state = await emiModel.getDecouplingState(deviceId);

    if (!state) {
      return null;
    }

    const fraudWindowActive = state.fraud_window_started_at && !state.fraud_window_ends_at;
    const fraudWindowExpired = state.fraud_window_ends_at ? new Date() >= new Date(state.fraud_window_ends_at) : false;

    return {
      deviceId,
      currentState: state.state,
      dealerNotifiedAt: state.dealer_notified_at,
      fraudWindowActive: state.fraud_window_ends_at && !fraudWindowExpired,
      fraudWindowEndsAt: state.fraud_window_ends_at,
      fraudFlagged: state.fraud_flag,
      fraudFlaggedBy: state.fraud_flagged_by,
      fraudFlaggedAt: state.fraud_flagged_at,
      fraudReason: state.fraud_reason,
      canAutoDecouple: await this.canAutoDecouple(deviceId),
      pendingAdminAction: state.state === DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE
    };
  }

  async logStateTransition(deviceId, fromState, toState, metadata = {}) {
    await require('../../config/database').query(
      `INSERT INTO decoupling_state_log (device_id, from_state, to_state, metadata, created_at)
       VALUES ($1, $2, $3, $4, NOW())`,
      [deviceId, fromState, toState, JSON.stringify(metadata)]
    );

    logger.info(`Decoupling state transition: ${deviceId} ${fromState} -> ${toState}`, metadata);
  }

  async checkAndTransitionFraudWindowExpired(deviceId) {
    const state = await emiModel.getDecouplingState(deviceId);

    if (!state || state.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      return null;
    }

    if (state.fraud_flag) {
      return null;
    }

    const windowEnd = new Date(state.fraud_window_ends_at);
    const now = new Date();

    if (now >= windowEnd) {
      return this.transitionToState(deviceId, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, {
        auto_transitioned: true,
        window_expired_at: windowEnd.toISOString()
      });
    }

    return null;
  }
}

module.exports = new DecouplingService();
module.exports.DECOUPLING_STATES = DECOUPLING_STATES;
module.exports.FRAUD_WINDOW_HOURS = FRAUD_WINDOW_HOURS;
