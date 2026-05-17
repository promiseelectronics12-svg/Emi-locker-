const crypto = require('crypto');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const decouplingModel = require('./decouplingModel');
const { DECOUPLING_STATES, VALID_TRANSITIONS } = require('./decouplingModel');
const scheduler = require('./decouplingScheduler');
const assignmentService = require('../assignments/assignmentService');
const firebaseService = require('../devices/firebaseService');
const amapiService = require('../devices/amapiService');
const lockCommandService = require('../lock/lockCommandService');
const fcmService = require('../notifications/fcm.service');
const padtService = require('../lock/padtService');

const RTOC_EXPIRY_HOURS = 24;

class DecouplingService {
  constructor() {
    this.rtocSecret = process.env.RTOC_SIGNING_SECRET;
    this.initialized = false;
  }

  initialize() {
    if (this.initialized) return;

    if (!this.rtocSecret) {
      if (process.env.NODE_ENV === 'production') {
        throw new Error('RTOC_SIGNING_SECRET must be set in production');
      }
      logger.warn('RTOC_SIGNING_SECRET not set, using dev fallback — NOT for production');
      this.rtocSecret = 'dev-rtoc-signing-secret-do-not-use';
    }

    scheduler.registerFraudWindowProcessor(this.handleFraudWindowExpired.bind(this));
    scheduler.registerAdminNotifyProcessor(this.handleAdminNotifyTimeout.bind(this));
    scheduler.registerAMAPIRetryProcessor(this.processAMAPIRetry.bind(this));
    this.initialized = true;
    logger.info('Decoupling service initialized');
  }

  // ============================================================
  // INITIATE — create decoupling record when EMI starts
  // ============================================================
  async initiateDecoupling(deviceId, emiScheduleId, actorId) {
    const existing = await decouplingModel.getByDeviceId(deviceId);
    if (existing) {
      if (existing.state === DECOUPLING_STATES.DEVICE_DECOUPLED) {
        throw new Error('Device is already decoupled');
      }
      return existing;
    }

    const decoupling = await decouplingModel.create(deviceId, emiScheduleId);

    await decouplingModel.createAuditLog(
      decoupling.id, deviceId,
      null, DECOUPLING_STATES.EMI_ACTIVE,
      actorId, 'system', 'DECOUPLING_INITIATED',
      { emiScheduleId }
    );

    logger.info(`Decoupling initiated for device ${deviceId}`);
    return decoupling;
  }

  // ============================================================
  // FINAL PAYMENT — auto-transition on full payment verification
  // ============================================================
  async handleFinalPayment(deviceId, paymentId, amount) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      throw new Error('No decoupling record found for device');
    }

    if (decoupling.state !== DECOUPLING_STATES.EMI_ACTIVE) {
      throw new Error(`Cannot process final payment: device is in state ${decoupling.state}`);
    }

    const isFullyPaid = await decouplingModel.verifyFinalPayment(deviceId, paymentId);
    if (!isFullyPaid) {
      return null;
    }

    return this.transition(deviceId, DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED, null, 'system', {
      finalPaymentId: paymentId,
      finalPaymentAmount: amount,
    });
  }

  // ============================================================
  // CORE STATE MACHINE — validates and executes transitions
  // ============================================================
  async transition(deviceId, newState, actorId, actorType = 'system', details = {}) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      throw new Error('No decoupling record found for device');
    }

    const currentState = decoupling.state;
    const validNext = VALID_TRANSITIONS[currentState] || [];
    if (!validNext.includes(newState)) {
      throw new Error(`Invalid state transition: ${currentState} → ${newState}`);
    }

    const updated = await decouplingModel.updateState(deviceId, newState, currentState, details);

    await decouplingModel.createAuditLog(
      decoupling.id, deviceId,
      currentState, newState,
      actorId, actorType, `TRANSITION_${currentState}_TO_${newState}`,
      details
    );

    // Fire post-transition handlers
    const handlers = {
      [DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED]: () => this.onFinalPaymentReceived(deviceId),
      [DECOUPLING_STATES.DEALER_NOTIFIED]: () => this.onDealerNotified(deviceId),
      [DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE]: () => this.onPendingAdminDecouple(deviceId),
      [DECOUPLING_STATES.DEVICE_DECOUPLED]: () => this.onDeviceDecoupled(deviceId, actorId),
      [DECOUPLING_STATES.FRAUD_CONFIRMED]: () => this.onFraudConfirmed(deviceId, actorId),
    };

    if (handlers[newState]) {
      await handlers[newState]();
    }

    logger.info(`Device ${deviceId} transitioned: ${currentState} → ${newState}`, details);
    return updated;
  }

  // ============================================================
  // POST-TRANSITION HANDLERS
  // ============================================================

  async onFinalPaymentReceived(deviceId) {
    await firebaseService.sendPushToDevice(deviceId, {
      title: 'EMI Complete - Final Payment Received',
      body: 'Your final EMI payment has been received. The decoupling process has started.',
      data: { type: 'DECOUPLING_INITIATED', deviceId, state: DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED },
    });

    logger.info(`Final payment received for device ${deviceId}, awaiting dealer notification`);
  }

  async onDealerNotified(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);

    // Set the 5-day fraud window
    await decouplingModel.setFraudWindow(deviceId);

    // Notify dealer in-app
    if (decoupling.dealer_id) {
      await db.query(
        `INSERT INTO notifications (user_id, type, title, body, data, created_at)
         VALUES ($1, 'in_app', 'Device EMI Complete - Review Window', $2, $3, NOW())`,
        [
          decoupling.dealer_id,
          `Device ${decoupling.imei} has completed EMI. Review within 5 days for fraud concerns. Decoupling will proceed automatically if no fraud is flagged.`,
          JSON.stringify({ type: 'DECOUPLING_DEALER_REVIEW', deviceId, windowDays: 5 }),
        ]
      );
    }

    // Schedule Bull queue delayed jobs for 5-day window
    await scheduler.scheduleFraudWindowCheck(deviceId);
    await scheduler.scheduleAdminNotification(deviceId);

    logger.info(`Dealer notified for device ${deviceId}, 5-day fraud window started`);
  }

  async onPendingAdminDecouple(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);

    await db.query(
      `INSERT INTO notifications (user_id, type, title, body, data, created_at)
       SELECT u.id, 'in_app', 'Decoupling Ready for Execution', $1, $2, NOW()
       FROM users u WHERE u.role = 'admin' AND u.status = 'active'`,
      [
        `Device ${decoupling.imei || deviceId} is ready for decoupling. No fraud flags raised during the 5-day window. Please execute decoupling.`,
        JSON.stringify({ type: 'DECOUPLING_ADMIN_ACTION', deviceId }),
      ]
    );

    logger.info(`Admin notified about pending decoupling for device ${deviceId}`);
  }

  async onFraudConfirmed(deviceId, adminId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) return;

    await db.query(
      `UPDATE devices SET restricted = true, restricted_at = NOW(), restricted_reason = $1 WHERE id = $2`,
      ['Fraud confirmed - device locked for investigation', deviceId]
    );

    await fcmService.sendToDevice(decoupling.fcm_token, {
      type: 'DEVICE_LOCKED',
      deviceId,
      reason: 'Fraud investigation',
      lockedAt: new Date().toISOString(),
    });

    if (decoupling.owner_id) {
      await db.query(
        `INSERT INTO notifications (user_id, type, title, body, data, created_at)
         VALUES ($1, 'in_app', 'Device Restricted', $2, $3, NOW())`,
        [
          decoupling.owner_id,
          `Your device has been restricted due to a fraud investigation. Please contact support for more information.`,
          JSON.stringify({ type: 'DEVICE_FRAUD_LOCK', deviceId }),
        ]
      );
    }

    logger.warn(`Device ${deviceId} locked due to fraud confirmation by admin ${adminId}`);
  }

  async onDeviceDecoupled(deviceId, actorId) {
    await db.query(
      `UPDATE devices SET status = 'decoupled', updated_at = NOW() WHERE id = $1`,
      [deviceId]
    );

    await db.query(
      `UPDATE emi_schedules SET status = 'completed', updated_at = NOW() WHERE device_id = $1 AND status = 'active'`,
      [deviceId]
    );

    await db.query(
      `UPDATE decoupling
       SET rtoc_code_hash = NULL,
           padt_token_id = NULL,
           padt_expires_at = NULL,
           updated_at = NOW()
       WHERE device_id = $1`,
      [deviceId]
    );

    // Close the ownership assignment — device is now unowned
    await assignmentService.closeAssignment(deviceId, 'decoupled');

    logger.info(`Device ${deviceId} marked as decoupled in database`);
  }

  // ============================================================
  // DEALER NOTIFICATION — triggers 5-day window
  // ============================================================
  async notifyDealer(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      throw new Error('No decoupling record found');
    }

    if (decoupling.state !== DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED) {
      throw new Error(`Cannot notify dealer: device is in state ${decoupling.state}`);
    }

    return this.transition(deviceId, DECOUPLING_STATES.DEALER_NOTIFIED, decoupling.dealer_id, 'system', {
      dealerNotifiedManually: true,
    });
  }

  // ============================================================
  // FRAUD FLAG — dealer flags with written evidence
  // Dealer CAN: flag with written evidence
  // Dealer CANNOT: block or delay decoupling
  // ============================================================
  async flagFraud(deviceId, dealerId, reason, evidenceUrl) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      throw new Error('No decoupling record found');
    }

    if (decoupling.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      throw new Error('Fraud can only be flagged during the 5-day dealer review window');
    }

    if (decoupling.fraud_window_ends_at && new Date(decoupling.fraud_window_ends_at) < new Date()) {
      throw new Error('The 5-day fraud review window has expired');
    }

    if (decoupling.dealer_id !== dealerId) {
      throw new Error('Only the assigned dealer can flag fraud for this device');
    }

    // Sanitize and validate reason
    const sanitizedReason = reason.replace(/<[^>]*>/g, '').trim();
    if (sanitizedReason.length < 10) {
      throw new Error('Fraud flag requires a written reason (minimum 10 characters)');
    }

    const updated = await decouplingModel.flagFraud(deviceId, dealerId, sanitizedReason, evidenceUrl);

    await decouplingModel.createAuditLog(
      decoupling.id, deviceId,
      DECOUPLING_STATES.DEALER_NOTIFIED, DECOUPLING_STATES.FRAUD_FLAGGED,
      dealerId, 'dealer', 'FRAUD_FLAGGED',
      { reason: sanitizedReason, evidenceUrl }
    );

    // Cancel auto-transition jobs — fraud is under review
    await scheduler.cancelFraudWindowCheck(deviceId);
    await scheduler.cancelAdminNotification(deviceId);

    // Notify all admins about the fraud flag
    await db.query(
      `INSERT INTO notifications (user_id, type, title, body, data, created_at)
       SELECT u.id, 'in_app', 'Fraud Flag Raised', $1, $2, NOW()
       FROM users u WHERE u.role = 'admin' AND u.status = 'active'`,
      [
        `Dealer has flagged device ${deviceId} for fraud. Reason: ${sanitizedReason}. Review required. Decoupling is NOT blocked — admin decides.`,
        JSON.stringify({ type: 'FRAUD_FLAG', deviceId, dealerId, reason: sanitizedReason }),
      ]
    );

    logger.warn(`Fraud flagged for device ${deviceId} by dealer ${dealerId}`, { reason: sanitizedReason });
    return updated;
  }

  // ============================================================
  // FRAUD CONFIRM / REJECT — admin decisions
  // ============================================================
  async confirmFraud(deviceId, adminId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      throw new Error('No decoupling record found');
    }

    if (decoupling.state !== DECOUPLING_STATES.FRAUD_FLAGGED) {
      throw new Error('Can only confirm fraud when device is in FRAUD_FLAGGED state');
    }

    const updated = await decouplingModel.confirmFraud(deviceId, adminId);

    await decouplingModel.createAuditLog(
      decoupling.id, deviceId,
      DECOUPLING_STATES.FRAUD_FLAGGED, DECOUPLING_STATES.FRAUD_CONFIRMED,
      adminId, 'admin', 'FRAUD_CONFIRMED',
      {}
    );

    logger.warn(`Fraud confirmed for device ${deviceId} by admin ${adminId}`);
    return updated;
  }

  async rejectFraud(deviceId, adminId) {
    const client = await decouplingModel.beginTransaction();
    try {
      const decoupling = await decouplingModel.getByDeviceIdInTransaction(client, deviceId);
      if (!decoupling) {
        throw new Error('No decoupling record found');
      }

      if (decoupling.state !== DECOUPLING_STATES.FRAUD_FLAGGED) {
        throw new Error('Can only reject fraud when device is in FRAUD_FLAGGED state');
      }

      const updated = await decouplingModel.updateState(deviceId, DECOUPLING_STATES.FRAUD_REJECTED, DECOUPLING_STATES.FRAUD_FLAGGED, {
        fraudRejected: true,
      }, client);

      await decouplingModel.createAuditLog(
        decoupling.id, deviceId,
        DECOUPLING_STATES.FRAUD_FLAGGED, DECOUPLING_STATES.FRAUD_REJECTED,
        adminId, 'admin', 'FRAUD_REJECTED',
        { fraudRejected: true }
      );

      const finalState = await decouplingModel.updateState(deviceId, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, DECOUPLING_STATES.FRAUD_REJECTED, {
        reason: 'Fraud rejected, proceeding to admin decoupling',
      }, client);

      await decouplingModel.createAuditLog(
        decoupling.id, deviceId,
        DECOUPLING_STATES.FRAUD_REJECTED, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE,
        adminId, 'admin', 'TRANSITION_FRAUD_REJECTED_TO_PENDING_ADMIN_DECOUPLE',
        { reason: 'Fraud rejected, proceeding to admin decoupling' }
      );

      await decouplingModel.commitTransaction(client);

      logger.info(`Fraud rejected for device ${deviceId} by admin ${adminId}, decoupling can proceed`);
      return finalState;
    } catch (error) {
      await decouplingModel.rollbackTransaction(client);
      throw error;
    }
  }

  // ============================================================
  // EXECUTE DECOUPLING — ADMIN ONLY, requires 2FA
  // ============================================================
async executeDecoupling(deviceId, adminId, totpCode) {
    const client = await decouplingModel.beginTransaction();
    try {
      let decoupling;
      try {
        decoupling = await decouplingModel.getByDeviceIdInTransaction(client, deviceId);
      } catch (err) {
        if (err.message.includes('Concurrent state transition')) {
          const concurrentError = new Error('Concurrent state transition detected. Please retry.');
          concurrentError.status = 409;
          throw concurrentError;
        }
        throw err;
      }
      if (!decoupling) {
        throw new Error('No decoupling record found');
      }

      if (decoupling.state === DECOUPLING_STATES.DEVICE_DECOUPLED) {
        throw new Error('Device is already decoupled');
      }

      if (decoupling.state !== DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE) {
        throw new Error(`Cannot execute decoupling: device is in state ${decoupling.state}. Must be PENDING_ADMIN_DECOUPLE.`);
      }

      if (!totpCode) {
        throw new Error('2FA code is required to execute decoupling');
      }

      const { verifyTOTP } = require('../auth/totp');
      const userResult = await db.query('SELECT totp_secret, role FROM users WHERE id = $1', [adminId]);
      if (userResult.rows.length === 0 || !userResult.rows[0].totp_secret) {
        throw new Error('Admin 2FA not configured');
      }

      if (userResult.rows[0].role !== 'admin') {
        throw new Error('Admin role required to execute decoupling');
      }

      const totpValid = verifyTOTP(totpCode, userResult.rows[0].totp_secret);
      if (!totpValid) {
        throw new Error('Invalid 2FA code');
      }

      await decouplingModel.setAdmin2FA(deviceId, adminId, client);

      const rtocCode = this.generateRTOC(deviceId);
      const rtocCodeHash = crypto.createHash('sha256').update(rtocCode).digest('hex');
      await decouplingModel.setRTOC(deviceId, rtocCodeHash, adminId, client);

      const encryptedRTOC = this.encryptRTOC(rtocCode, deviceId);
      const rtocKeySalt = crypto.createHash('sha256').update(deviceId).digest('hex').substring(0, 16);

      const signedCommand = await lockCommandService.generateSignedCommand({
        deviceImei: decoupling.imei || '',
        actionType: 'DECOUPLE',
        lockLevel: 'NONE',
        metadata: { rtocCode, action: 'DECOUPLE', deviceId }
      });

      let fcmSuccess = false;
      let fcmFailureReason = null;

      try {
        const fcmResult = await fcmService.sendToDevice(decoupling.fcm_token, {
          type: 'DECOUPLE_COMMAND',
          command: 'DECOUPLE',
          commandType: 'DECOUPLE',
          deviceId,
          deviceImei: decoupling.imei || '',
          lockLevel: 'NONE',
          encryptedRTOC,
          rtocKeySalt,
          signature: signedCommand.hmacSignature,
          hmacSignature: signedCommand.hmacSignature,
          timestamp: String(signedCommand.timestamp),
          nonce: signedCommand.nonce,
          serverId: process.env.SERVER_ID || 'server-001',
        });

        fcmSuccess = fcmResult.success;
        if (!fcmSuccess) {
          fcmFailureReason = 'FCM delivery failed';
        }
      } catch (error) {
        fcmFailureReason = error.message;
        logger.error(`FCM failed for decouple command on device ${deviceId}:`, error);
      }

      await decouplingModel.markFCMSent(deviceId, fcmSuccess, fcmFailureReason, client);

      let amapiSuccess = false;
      try {
        await amapiService.initialize();
        const enterpriseId = process.env.AMAPI_ENTERPRISE_ID;
        if (!enterpriseId) throw new Error('AMAPI enterprise not configured');
        await amapiService.deleteDevice(enterpriseId, decoupling.amapi_device_name);
        amapiSuccess = true;
        logger.info(`AMAPI device deleted for ${deviceId}: ${decoupling.amapi_device_name}`);
      } catch (error) {
        logger.error(`AMAPI deletion failed for device ${deviceId}:`, error);
        try {
          await this.scheduleAMAPIRetry(deviceId);
        } catch (retryError) {
          logger.error(`Failed to schedule AMAPI retry for device ${deviceId}:`, retryError);
        }
      }

      await decouplingModel.markAMAPIDeleted(deviceId, amapiSuccess, client);

      const updated = await decouplingModel.updateState(deviceId, DECOUPLING_STATES.DEVICE_DECOUPLED, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, {
        fcmSuccess,
        signedCommandId: signedCommand.nonce,
      }, client);

      await decouplingModel.createAuditLog(
        decoupling.id, deviceId,
        DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, DECOUPLING_STATES.DEVICE_DECOUPLED,
        adminId, 'admin', 'TRANSITION_PENDING_ADMIN_DECOUPLE_TO_DEVICE_DECOUPLED',
        { fcmSuccess, signedCommandId: signedCommand.nonce }
      );

      await client.query(
        `UPDATE devices
         SET unlock_code_hash = NULL,
             unlock_code_salt = NULL,
             managed_google_account = NULL,
             updated_at = NOW()
         WHERE id = $1`,
        [deviceId]
      );

      await client.query(
        `UPDATE devices SET status = 'decoupled', updated_at = NOW() WHERE id = $1`,
        [deviceId]
      );

      await client.query(
        `UPDATE emi_schedules SET status = 'completed', updated_at = NOW() WHERE device_id = $1 AND status = 'active'`,
        [deviceId]
      );

      await client.query(
        `UPDATE decoupling
         SET rtoc_code_hash = NULL,
             padt_token_id = NULL,
             padt_expires_at = NULL,
             updated_at = NOW()
         WHERE device_id = $1`,
        [deviceId]
      );

      await decouplingModel.commitTransaction(client);

      logger.info(`Device ${deviceId} fully decoupled by admin ${adminId}`, {
        fcmSuccess,
        amapiSuccess,
      });

      return {
        success: true,
        deviceId,
        fcmDelivered: fcmSuccess,
        amapiDeleted: amapiSuccess,
        decoupledAt: new Date().toISOString(),
      };
    } catch (error) {
      await decouplingModel.rollbackTransaction(client);
      logger.error(`Decoupling failed for device ${deviceId}:`, error);
      throw error;
    }
  }

  // ============================================================
  // AMAPI RETRY QUEUE — retry failed AMAPI deletions
  // ============================================================
  async scheduleAMAPIRetry(deviceId) {
    await decouplingModel.updateAMAPIDeletionStatus(deviceId, 'failed_retrying');
    const queue = scheduler.getAMAPIRetryQueue();
    if (queue) {
      await queue.add(
        'amapi-retry',
        { deviceId, attempt: 1 },
        { delay: 60000, jobId: `amapi-retry-${deviceId}` }
      );
      logger.info(`AMAPI retry scheduled for device ${deviceId}`);
    }
  }

  async processAMAPIRetry(deviceId, attempt = 1) {
    const MAX_ATTEMPTS = 5;
    if (attempt >= MAX_ATTEMPTS) {
      await decouplingModel.updateAMAPIDeletionStatus(deviceId, 'failed_permanent');
      logger.error(`AMAPI retry failed permanently for device ${deviceId} after ${MAX_ATTEMPTS} attempts`);
      return;
    }

    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling || !decoupling.amapi_device_name) {
      return;
    }

    try {
      await amapiService.initialize();
      const enterpriseId = process.env.AMAPI_ENTERPRISE_ID;
      await amapiService.deleteDevice(enterpriseId, decoupling.amapi_device_name);
      await decouplingModel.updateAMAPIDeletionStatus(deviceId, 'completed');
      logger.info(`AMAPI retry succeeded for device ${deviceId} on attempt ${attempt + 1}`);
    } catch (error) {
      logger.error(`AMAPI retry failed for device ${deviceId} (attempt ${attempt + 1}):`, error);
      const queue = scheduler.getAMAPIRetryQueue();
      if (queue) {
        await queue.add(
          'amapi-retry',
          { deviceId, attempt: attempt + 1 },
          { delay: 120000 * attempt, jobId: `amapi-retry-${deviceId}` }
        );
      }
    }
  }

  // ============================================================
  // BULL QUEUE HANDLERS — called by scheduler after 5-day delay
  // ============================================================

  async handleFraudWindowExpired(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      logger.warn(`Fraud window expired but no decoupling record for device ${deviceId}`);
      return;
    }

    if (decoupling.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      logger.info(`Fraud window expired for device ${deviceId} but state is ${decoupling.state}, skipping`);
      return;
    }

    if (decoupling.fraud_flag) {
      logger.info(`Fraud window expired for device ${deviceId} but fraud flag is set, skipping`);
      return;
    }

    // No fraud flag raised during 5-day window → auto-transition to PENDING_ADMIN_DECOUPLE
    await this.transition(deviceId, DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, null, 'scheduler', {
      reason: 'Fraud window expired with no flags — auto-transitioned',
      autoTransition: true,
    });
  }

  async handleAdminNotifyTimeout(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) {
      logger.warn(`Admin notify timeout but no decoupling record for device ${deviceId}`);
      return;
    }

    if (decoupling.state !== DECOUPLING_STATES.DEALER_NOTIFIED) {
      logger.info(`Admin notify timeout for device ${deviceId} but state is ${decoupling.state}, skipping`);
      return;
    }

    if (decoupling.fraud_flag) {
      logger.info(`Admin notify timeout for device ${deviceId} but fraud flag is set, skipping`);
      return;
    }

    await db.query(
      `INSERT INTO notifications (user_id, type, title, body, data, created_at)
       SELECT u.id, 'in_app', 'Decoupling Action Required', $1, $2, NOW()
       FROM users u WHERE u.role = 'admin' AND u.status = 'active'`,
      [
        `Device ${decoupling.imei || deviceId} has passed the 5-day fraud window without flags. Please execute decoupling.`,
        JSON.stringify({ type: 'DECOUPLING_ADMIN_REQUIRED', deviceId }),
      ]
    );

    logger.info(`Admin notified for device ${deviceId} via timeout handler`);
  }

  // ============================================================
  // RTOC — Release Token One-time Code (HMAC-based, 24h expiry)
  // ============================================================
  generateRTOC(deviceId) {
    const timestamp = Date.now().toString(36);
    const randomBytes = crypto.randomBytes(6).toString('hex');
    const payload = `${deviceId}:${timestamp}:${randomBytes}`;

    const hmac = crypto.createHmac('sha256', this.rtocSecret);
    hmac.update(payload);
    const signature = hmac.digest('hex').substring(0, 10);

    return `RTOC-${timestamp}-${randomBytes}-${signature}`.toUpperCase();
  }

  verifyRTOC(rtocCode, deviceId) {
    try {
      const parts = rtocCode.split('-');
      if (parts.length !== 4 || parts[0] !== 'RTOC') {
        return false;
      }

      const timestamp = parseInt(parts[1], 36);
      const randomBytes = parts[2];
      const providedSignature = parts[3];

      if (Date.now() - timestamp > RTOC_EXPIRY_HOURS * 3600000) {
        return false;
      }

      const payload = `${deviceId}:${parts[1]}:${randomBytes}`;
      const hmac = crypto.createHmac('sha256', this.rtocSecret);
      hmac.update(payload);
      const expectedSignature = hmac.digest('hex').substring(0, 10);

      return crypto.timingSafeEqual(
        Buffer.from(providedSignature, 'utf8'),
        Buffer.from(expectedSignature, 'utf8')
      );
    } catch (error) {
      logger.error('RTOC verification error:', error);
      return false;
    }
  }

  encryptRTOC(rtocCode, deviceId) {
    const algorithm = 'aes-256-gcm';
    const key = this.deriveRTOCKey(deviceId);
    const iv = crypto.randomBytes(16);

    const cipher = crypto.createCipheriv(algorithm, key, iv);
    let encrypted = cipher.update(rtocCode, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    const authTag = cipher.getAuthTag();
    return `${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted}`;
  }

  decryptRTOC(encryptedRTOC, deviceId) {
    const algorithm = 'aes-256-gcm';
    const key = this.deriveRTOCKey(deviceId);

    try {
      const parts = encryptedRTOC.split(':');
      if (parts.length !== 3) return null;

      const iv = Buffer.from(parts[0], 'hex');
      const authTag = Buffer.from(parts[1], 'hex');
      const encrypted = parts[2];

      const decipher = crypto.createDecipheriv(algorithm, key, iv);
      decipher.setAuthTag(authTag);

      let decrypted = decipher.update(encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');
      return decrypted;
    } catch (error) {
      logger.error('RTOC decryption failed:', error.message);
      return null;
    }
  }

  deriveRTOCKey(deviceId) {
    const salt = `rtoc-${deviceId}-${process.env.RTOC_ENCRYPTION_KEY || 'dev-rtockey'}`;
    return crypto.createHash('sha256').update(salt).digest();
  }

  // ============================================================
  // STATUS & QUERIES
  // ============================================================
  async getDecouplingStatus(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) return null;

    const now = new Date();
    const fraudWindowActive = decoupling.state === DECOUPLING_STATES.DEALER_NOTIFIED &&
      decoupling.fraud_window_ends_at &&
      new Date(decoupling.fraud_window_ends_at) > now;

    const fraudWindowExpired = decoupling.fraud_window_ends_at &&
      new Date(decoupling.fraud_window_ends_at) <= now;

    return {
      deviceId,
      currentState: decoupling.state,
      dealerNotifiedAt: decoupling.dealer_notified_at,
      fraudWindowStartedAt: decoupling.fraud_window_started_at,
      fraudWindowEndsAt: decoupling.fraud_window_ends_at,
      fraudWindowActive,
      fraudWindowExpired,
      fraudFlagged: decoupling.fraud_flag,
      fraudFlaggedBy: decoupling.fraud_flagged_by,
      fraudFlaggedAt: decoupling.fraud_flagged_at,
      fraudReason: decoupling.fraud_reason,
      fraudEvidenceUrl: decoupling.fraud_evidence_url,
      rtocCodeHash: decoupling.rtoc_code_hash ? decoupling.rtoc_code_hash.substring(0, 8) : null,
      fcmDelivered: decoupling.fcm_delivered,
      padtIssued: !!decoupling.padt_token_id,
      padtExpiresAt: decoupling.padt_expires_at,
      amapiDeleted: decoupling.amapi_delete_success,
      decoupledAt: decoupling.decoupled_at,
      decoupledBy: decoupling.decoupled_by,
      canExecute: decoupling.state === DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE,
      isDecoupled: decoupling.state === DECOUPLING_STATES.DEVICE_DECOUPLED,
    };
  }

  async getAuditTrail(deviceId) {
    return decouplingModel.getAuditLogs(deviceId);
  }

  async getStats() {
    return decouplingModel.getDecouplingStats();
  }

  // ============================================================
  // PADT CHECK — device calls this on network reconnect
  // ============================================================
  async checkPADTOnReconnect(deviceId) {
    const decoupling = await decouplingModel.getByDeviceId(deviceId);
    if (!decoupling) return null;

    if (decoupling.state !== DECOUPLING_STATES.DEVICE_DECOUPLED) return null;
    if (!decoupling.padt_token_id) return null;
    if (decoupling.padt_expires_at && new Date(decoupling.padt_expires_at) < new Date()) {
      return { expired: true };
    }

    return { pending: true };
  }
}

module.exports = new DecouplingService();
module.exports.DECOUPLING_STATES = DECOUPLING_STATES;
