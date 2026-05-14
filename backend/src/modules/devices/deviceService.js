const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const amapiService = require('./amapiService');
const firebaseService = require('./firebaseService');
const hardwareBindingService = require('./hardwareBindingService');
const commandSigningService = require('./commandSigningService');

function isFrpEnabled() {
  return String(process.env.FRP_ENABLED || 'true').toLowerCase() !== 'false';
}

function parseEnvList(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function getFrpAdminOwnedAccounts(device, extraAccount = null) {
  return Array.from(
    new Set(
      [
        extraAccount,
        device?.managed_google_account,
        ...parseEnvList(process.env.FRP_ADMIN_OWNED_ACCOUNTS)
      ].filter(Boolean)
    )
  );
}

class DeviceService {
  constructor() {
    this.enterpriseId = process.env.AMAPI_ENTERPRISE_ID;
  }

  async logAuditEvent({
    actor,
    action,
    deviceId,
    metadata = {},
    ipAddress = null,
    result = 'success'
  }) {
    try {
      await db.query(
        `INSERT INTO audit_log (actor, action, device_id, metadata, ip_address, result, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
        [actor, action, deviceId, JSON.stringify(metadata), ipAddress, result]
      );
    } catch (error) {
      logger.error('Failed to write audit log:', error);
    }
  }

  async storeUnlockCode(deviceId, unlockCode) {
    const salt = crypto.randomBytes(16).toString('hex');
    const hashedCode = crypto.pbkdf2Sync(unlockCode, salt, 10000, 32, 'sha256').toString('hex');

    await db.query(
      `UPDATE devices SET unlock_code_hash = $1, unlock_code_salt = $2, updated_at = NOW() WHERE id = $3`,
      [hashedCode, salt, deviceId]
    );

    logger.info(`Unlock code stored for device: ${deviceId}`);
  }

  async verifyUnlockCode(deviceId, providedCode) {
    const result = await db.query(
      `SELECT unlock_code_hash, unlock_code_salt FROM devices WHERE id = $1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      throw new Error('Device not found');
    }

    const { unlock_code_hash, unlock_code_salt } = result.rows[0];

    if (!unlock_code_hash || !unlock_code_salt) {
      return true;
    }

    const hashedProvided = crypto
      .pbkdf2Sync(providedCode, unlock_code_salt, 10000, 32, 'sha256')
      .toString('hex');

    try {
      return crypto.timingSafeEqual(
        Buffer.from(hashedProvided, 'hex'),
        Buffer.from(unlock_code_hash, 'hex')
      );
    } catch (error) {
      return false;
    }
  }

  async clearUnlockCode(deviceId) {
    await db.query(
      `UPDATE devices SET unlock_code_hash = NULL, unlock_code_salt = NULL, updated_at = NOW() WHERE id = $1`,
      [deviceId]
    );

    logger.info(`Unlock code cleared for device: ${deviceId}`);
  }

  async enrollDevice({
    enrollmentToken,
    imei,
    serialNumber,
    socId,
    dealerId,
    userId,
    deviceName,
    model,
    brand
  }) {
    await amapiService.initialize();

    const validToken = await this.validateEnrollmentToken(enrollmentToken, dealerId);
    if (!validToken) {
      throw new Error('Invalid or expired enrollment token');
    }

    const existingDevice = await db.query(
      'SELECT id FROM devices WHERE imei = $1 AND status != $2',
      [imei, 'decoupled']
    );

    if (existingDevice.rows.length > 0) {
      throw new Error('Device is already enrolled in the system');
    }

    // Fetch dealer's phone number to store on the device record.
    // The customer's locked screen will display this so they know who to call.
    // The customer app also uses this to verify incoming SMS OTP authenticity.
    let dealerPhone = null;
    try {
      const dealerRow = await db.query(
        'SELECT phone FROM dealers WHERE id = $1 OR user_id = $1 LIMIT 1',
        [dealerId]
      );
      dealerPhone = dealerRow.rows[0]?.phone || null;
    } catch (e) {
      logger.warn('Failed to fetch dealer phone during enrollment', { dealerId, error: e.message });
    }

    const deviceUuid = uuidv4();
    const managedAccountEmail = `device-${deviceUuid.split('-')[0]}@${process.env.AMAPI_MANAGED_DOMAIN || 'emilocker-mdm.com'}`;

    const amapiDevicePayload = {
      managementMode: 'DEVICE_OWNER',
      policyName: `enterprises/${this.enterpriseId}/policies/default`,
      enrollmentToken,
      deviceOwnerOverrides: {
        managementDisabled: false
      }
    };

    let amapiDevice;
    try {
      amapiDevice = await amapiService.createDevice(this.enterpriseId, amapiDevicePayload);
    } catch (error) {
      logger.error('Failed to create AMAPI device:', error);
      throw new Error('Failed to register device with Android Management API');
    }

    const deviceId = uuidv4();

    const result = await db.query(
      `INSERT INTO devices (
        id, amapi_device_name, amapi_device_id, imei, serial_number, soc_id,
        managed_google_account, dealer_id, owner_id, device_name, model, brand,
        enrollment_token, dealer_phone, status, enrolled_at, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, 'enrolled', NOW(), NOW(), NOW())
      RETURNING *`,
      [
        deviceId,
        amapiDevice.name,
        amapiDevice.name.split('/').pop(),
        imei,
        serialNumber,
        socId,
        managedAccountEmail,
        dealerId,
        userId,
        deviceName,
        model,
        brand,
        enrollmentToken,
        dealerPhone
      ]
    );

    const device = result.rows[0];

    await hardwareBindingService.storeHardwareBinding(deviceId, imei, serialNumber, socId);

    await firebaseService.writeEnrollmentData(deviceId, {
      enrollmentToken,
      managedGoogleAccount: managedAccountEmail,
      amapiDeviceName: amapiDevice.name,
      dealerId,
      ownerId: userId,
      deviceName,
      model,
      brand,
      enrolledAt: new Date().toISOString()
    });

    await this.pushInitialPolicies(deviceId);

    await this.bindFrpAccount(deviceId, managedAccountEmail);

    await this.markTokenAsUsed(enrollmentToken);

    logger.info(`Device enrolled successfully: ${deviceId}`, {
      imei,
      dealerId,
      ownerId: userId,
      amapiDeviceId: amapiDevice.name.split('/').pop()
    });

    return {
      deviceId,
      amapiDeviceName: amapiDevice.name,
      amapiDeviceId: amapiDevice.name.split('/').pop(),
      managedGoogleAccount: managedAccountEmail,
      status: 'enrolled',
      enrolledAt: device.enrolled_at
    };
  }

  async validateEnrollmentToken(token, requestingDealerId = null) {
    if (!token || typeof token !== 'string') {
      return false;
    }

    const result = await db.query(
      `SELECT id, expires_at, used, dealer_id
       FROM enrollment_tokens
       WHERE token = $1`,
      [token]
    );

    if (result.rows.length === 0) {
      logger.warn('Enrollment token not found');
      return false;
    }

    const tokenRecord = result.rows[0];

    if (tokenRecord.expires_at && new Date(tokenRecord.expires_at) < new Date()) {
      logger.warn('Enrollment token has expired');
      return false;
    }

    if (tokenRecord.used) {
      logger.warn('Enrollment token has already been used');
      return false;
    }

    if (requestingDealerId !== null && tokenRecord.dealer_id !== requestingDealerId) {
      logger.warn('Enrollment token dealer mismatch', {
        tokenDealer: tokenRecord.dealer_id,
        requestingDealer: requestingDealerId
      });
      return false;
    }

    return true;
  }

  async bindFrpAccount(deviceId, managedAccountEmail) {
    await amapiService.initialize();

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      logger.warn(`Device not found for FRP binding: ${deviceId}`);
      return;
    }

    const [accountEmail] = getFrpAdminOwnedAccounts(device, managedAccountEmail);
    if (!isFrpEnabled() || !accountEmail) {
      logger.warn(
        `FRP binding skipped for device ${deviceId}: FRP disabled or no admin-owned account configured`
      );
      return;
    }

    try {
      await amapiService.bindManagedAccount(
        this.enterpriseId,
        device.amapi_device_name,
        accountEmail
      );

      await firebaseService.writeDeviceMetadata(deviceId, {
        frpEnabled: true,
        frpAccountEmail: accountEmail,
        frpBoundAt: new Date().toISOString()
      });

      logger.info(`FRP account bound for device: ${deviceId}`);
    } catch (error) {
      logger.error(`Failed to bind FRP account for device ${deviceId}:`, error);
    }
  }

  async verifyFrpState(deviceId) {
    await amapiService.initialize();

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    try {
      const amapiDevice = await amapiService.getDevice(this.enterpriseId, device.amapi_device_name);
      const frpState = amapiDevice.factoryResetProtection || {};

      return {
        deviceId,
        frpEnabled: frpState.enabled || false,
        frpAccounts: frpState.adminOwnedAccounts || [],
        verifiedAt: new Date().toISOString()
      };
    } catch (error) {
      logger.error(`Failed to verify FRP state for device ${deviceId}:`, error);
      throw error;
    }
  }

  async markTokenAsUsed(token) {
    await db.query(`UPDATE enrollment_tokens SET used = true, used_at = NOW() WHERE token = $1`, [
      token
    ]);
  }

  async pushInitialPolicies(deviceId) {
    await amapiService.initialize();

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    const policy = {
      adbEnabled: false,
      developmentSettingsEnabled: false,
      installUnknownSourcesAllowed: false,
      locationMode: 'LOCATION_MODE_OFF',
      persistentPreferredActivities: [],
      statusBarSettings: {
        disabled: false
      }
    };

    try {
      await amapiService.setDevicePolicy(this.enterpriseId, device.amapi_device_name, policy);

      await firebaseService.writePolicyStatus(deviceId, {
        policiesApplied: {
          adbEnabled: false,
          developmentSettingsEnabled: false,
          installUnknownSourcesAllowed: false,
          locationMode: 'LOCATION_MODE_OFF'
        },
        appliedAt: new Date().toISOString(),
        source: 'initial_enrollment'
      });

      logger.info(`Initial policies pushed to device: ${deviceId}`);
    } catch (error) {
      logger.error(`Failed to push initial policies to device ${deviceId}:`, error);
      throw error;
    }
  }

  async applyDeviceOwnerPolicies(deviceId) {
    await amapiService.initialize();

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    const frpAccounts = getFrpAdminOwnedAccounts(device);
    const frpEnabled = isFrpEnabled() && frpAccounts.length > 0;
    if (isFrpEnabled() && frpAccounts.length === 0) {
      logger.warn(`FRP policy has no admin-owned account configured for device: ${deviceId}`);
    }

    const policies = {
      globalSettings: {
        adb_enabled: 0,
        development_settings_enabled: 0
      },
      secureSettings: {
        install_non_market_apps: 0
      },
      usbDataSignalingEnabled: false,
      factoryResetProtection: {
        enabled: frpEnabled,
        adminOwnedAccounts: frpAccounts
      }
    };

    try {
      for (const [setting, value] of Object.entries(policies.globalSettings)) {
        await amapiService.setGlobalSetting(
          this.enterpriseId,
          device.amapi_device_name,
          setting,
          value
        );
      }

      for (const [setting, value] of Object.entries(policies.secureSettings)) {
        await amapiService.setSecureSetting(
          this.enterpriseId,
          device.amapi_device_name,
          setting,
          value
        );
      }

      const policyPayload = {
        adbEnabled: false,
        developmentSettingsEnabled: false,
        installUnknownSourcesAllowed: false,
        usbDataSignalingEnabled: false,
        factoryResetProtection: {
          enabled: frpEnabled,
          adminOwnedAccounts: frpAccounts
        }
      };

      await amapiService.setDevicePolicy(
        this.enterpriseId,
        device.amapi_device_name,
        policyPayload
      );

      await firebaseService.writePolicyStatus(deviceId, {
        policiesApplied: {
          ADB_ENABLED: 0,
          DEVELOPMENT_SETTINGS_ENABLED: 0,
          INSTALL_NON_MARKET_APPS: 0,
          USB_DATA_SIGNALING: false
        },
        appliedAt: new Date().toISOString(),
        source: 'device_owner_policy'
      });

      await db.query(
        `UPDATE devices SET policy_last_applied = NOW(), updated_at = NOW() WHERE id = $1`,
        [deviceId]
      );

      await this.logAuditEvent({
        actor: 'system',
        action: 'APPLY_POLICY',
        deviceId,
        metadata: { policy: 'device_owner_policy' },
        result: 'success'
      });

      logger.info(`Device Owner policies applied to device: ${deviceId}`);

      return {
        success: true,
        deviceId,
        policies
      };
    } catch (error) {
      logger.error(`Failed to apply Device Owner policies to device ${deviceId}:`, error);
      throw error;
    }
  }

  async getDeviceById(deviceId) {
    const result = await db.query(
      `SELECT d.*,
              u.name as owner_name, u.email as owner_email, u.phone as owner_phone,
              dl.name as dealer_name, dl.email as dealer_email
       FROM devices d
       LEFT JOIN users u ON d.owner_id = u.id
       LEFT JOIN dealers dl ON d.dealer_id = dl.id
       WHERE d.id = $1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return result.rows[0];
  }

  async getDeviceInfo(deviceId, verifyHardware = true) {
    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    let hardwareBinding = null;
    if (verifyHardware) {
      hardwareBinding = await hardwareBindingService.checkHardwareBindingExists(deviceId);
    }

    let firebaseStatus = null;
    try {
      firebaseStatus = await firebaseService.getDeviceStatus(deviceId);
    } catch (error) {
      logger.warn(`Failed to get Firebase status for device ${deviceId}:`, error.message);
    }

    let amapiDevice = null;
    try {
      await amapiService.initialize();
      amapiDevice = await amapiService.getDevice(this.enterpriseId, device.amapi_device_name);
    } catch (error) {
      logger.warn(`Failed to get AMAPI device ${device.amapi_device_name}:`, error.message);
    }

    return {
      id: device.id,
      amapiDeviceId: device.amapi_device_id,
      amapiDeviceName: device.amapi_device_name,
      imei: device.imei,
      serialNumber: device.serial_number,
      deviceName: device.device_name,
      model: device.model,
      brand: device.brand,
      status: device.status,
      managedGoogleAccount: device.managed_google_account,
      enrollmentToken: device.enrollment_token,
      enrolledAt: device.enrolled_at,
      policyLastApplied: device.policy_last_applied,
      owner: device.owner_id
        ? {
            id: device.owner_id,
            name: device.owner_name,
            email: device.owner_email,
            phone: device.owner_phone
          }
        : null,
      dealer: device.dealer_id
        ? {
            id: device.dealer_id,
            name: device.dealer_name,
            email: device.dealer_email
          }
        : null,
      hardwareBinding,
      realtimeStatus: firebaseStatus,
      amapiStatus: amapiDevice
        ? {
            state: amapiDevice.state,
            managementMode: amapiDevice.managementMode,
            lastStatusReportTime: amapiDevice.lastStatusReportTime,
            enrollmentTime: amapiDevice.enrollmentTime
          }
        : null
    };
  }

  async updateFcmToken(deviceId, fcmToken) {
    if (!fcmToken || typeof fcmToken !== 'string') {
      throw new Error('Valid FCM token is required');
    }

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    await db.query(
      `UPDATE devices SET fcm_token = $1, fcm_token_updated_at = NOW(), updated_at = NOW() WHERE id = $2`,
      [fcmToken, deviceId]
    );

    await firebaseService.writeDeviceMetadata(deviceId, {
      fcmToken,
      fcmTokenUpdatedAt: new Date().toISOString()
    });

    logger.info(`FCM token updated for device: ${deviceId}`);

    return {
      success: true,
      deviceId,
      fcmTokenUpdatedAt: new Date().toISOString()
    };
  }

  async getDeviceStatus(deviceId) {
    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    const lockState = await firebaseService.getDeviceLockState(deviceId);
    const commandHistory = await firebaseService.getCommandHistory(deviceId, 10);

    // EMI completion check — when all installments are paid the dealer permanently
    // loses the right to lock the device. The device app uses this flag to disable
    // the lock screen entirely after the last payment is confirmed.
    let emiFullyPaid = false;
    let emiInstallmentsPaid = 0;
    let emiInstallmentsTotal = 0;
    let activeGraceUnlock = null;
    try {
      const emiResult = await db.query(
        `SELECT es.duration                        AS total,
                COUNT(ep.id) FILTER (WHERE ep.status = 'completed') AS paid
         FROM   emi_schedules es
         LEFT JOIN emi_payments ep ON ep.emi_schedule_id = es.id
         WHERE  es.device_id = $1 AND es.status = 'active'
         GROUP  BY es.duration
         LIMIT  1`,
        [deviceId]
      );
      if (emiResult.rows.length) {
        const row = emiResult.rows[0];
        emiInstallmentsPaid = Number(row.paid) || 0;
        emiInstallmentsTotal = Number(row.total) || 0;
        emiFullyPaid = emiInstallmentsTotal > 0 && emiInstallmentsPaid >= emiInstallmentsTotal;
      }

      // Active dealer-issued grace unlock (so device knows how long to stay unlocked)
      const graceResult = await db.query(
        `SELECT grace_hours, expires_at
         FROM   grace_unlock_events
         WHERE  device_id = $1 AND revoked = FALSE AND expires_at > NOW()
         ORDER  BY issued_at DESC
         LIMIT  1`,
        [deviceId]
      );
      if (graceResult.rows.length) {
        activeGraceUnlock = {
          grace_hours: graceResult.rows[0].grace_hours,
          expires_at: graceResult.rows[0].expires_at
        };
      }
    } catch (_) {
      // Non-fatal — EMI or grace_unlock_events tables may not exist yet
    }

    return {
      deviceId,
      deviceStatus: device.status,
      lockState: lockState.lockState,
      isLocked: lockState.isLocked,
      lockReason: lockState.lockReason,
      lastUpdated: lockState.lastUpdated,
      recentCommands: commandHistory,
      dealer_phone: device.dealer_phone || null,
      grace_expires_at: device.grace_expires_at || null,
      emi: {
        fully_paid: emiFullyPaid,
        installments_paid: emiInstallmentsPaid,
        installments_total: emiInstallmentsTotal
      },
      active_grace_unlock: activeGraceUnlock
    };
  }

  async updateDeviceStatus(deviceId, status, metadata = {}) {
    const validStatuses = [
      'active',
      'locked',
      'unlocked',
      'stolen',
      'disabled',
      'enrolled',
      'decoupled'
    ];
    if (!validStatuses.includes(status)) {
      throw new Error(`Invalid status: ${status}`);
    }

    const result = await db.query(
      `UPDATE devices SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
      [status, deviceId]
    );

    if (result.rows.length === 0) {
      throw new Error('Device not found');
    }

    if (status === 'locked') {
      await firebaseService.updateLockState(deviceId, 'locked', {
        reason: metadata.reason,
        lockedBy: metadata.lockedBy
      });
    } else if (status === 'active' || status === 'unlocked') {
      await firebaseService.updateLockState(deviceId, 'unlocked', {
        reason: metadata.reason,
        unlockedBy: metadata.unlockedBy
      });
    }

    logger.info(`Device status updated: ${deviceId} -> ${status}`);

    return {
      deviceId,
      status,
      updatedAt: result.rows[0].updated_at
    };
  }

  async lockDevice(deviceId, reason, lockedBy, unlockCode = null) {
    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    const result = await db.query(
      `UPDATE devices SET status = 'locked', updated_at = NOW() WHERE id = $1 RETURNING *`,
      [deviceId]
    );

    if (unlockCode) {
      await this.storeUnlockCode(deviceId, unlockCode);
    }

    await firebaseService.updateLockState(deviceId, 'locked', {
      reason,
      lockedBy
    });

    const signedCommand = await commandSigningService.createAndStoreSignedCommand(
      deviceId,
      'lock',
      { reason, lockedBy },
      device.imei
    );

    await firebaseService.writeCommandHistory(deviceId, {
      type: 'lock',
      reason,
      executedBy: lockedBy,
      status: 'success',
      signedCommand
    });

    await this.logAuditEvent({
      actor: lockedBy,
      action: 'LOCK_DEVICE',
      deviceId,
      metadata: { reason },
      result: 'success'
    });

    logger.info(`Device locked: ${deviceId}`, { reason, lockedBy });

    return {
      deviceId,
      status: 'locked',
      lockReason: reason
    };
  }

  async unlockDevice(deviceId, reason, unlockedBy, unlockCode = null) {
    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    if (unlockCode) {
      const isCodeValid = await this.verifyUnlockCode(deviceId, unlockCode);
      if (!isCodeValid) {
        await this.logAuditEvent({
          actor: unlockedBy,
          action: 'UNLOCK_DEVICE',
          deviceId,
          metadata: { reason },
          result: 'failed'
        });
        throw new Error('Invalid unlock code');
      }
      await this.clearUnlockCode(deviceId);
    }

    const result = await db.query(
      `UPDATE devices SET status = 'active', updated_at = NOW() WHERE id = $1 RETURNING *`,
      [deviceId]
    );

    await firebaseService.updateLockState(deviceId, 'unlocked', {
      reason,
      unlockedBy
    });

    const signedCommand = await commandSigningService.createAndStoreSignedCommand(
      deviceId,
      'unlock',
      { reason, unlockedBy },
      device.imei
    );

    await firebaseService.writeCommandHistory(deviceId, {
      type: 'unlock',
      reason,
      executedBy: unlockedBy,
      status: 'success',
      signedCommand
    });

    await this.logAuditEvent({
      actor: unlockedBy,
      action: 'UNLOCK_DEVICE',
      deviceId,
      metadata: { reason },
      result: 'success'
    });

    logger.info(`Device unlocked: ${deviceId}`, { reason, unlockedBy });

    return {
      deviceId,
      status: 'active',
      unlockReason: reason
    };
  }

  async decoupleDevice(deviceId) {
    await amapiService.initialize();

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    try {
      await amapiService.deleteDevice(this.enterpriseId, device.amapi_device_name);
    } catch (error) {
      logger.warn(`Failed to delete AMAPI device ${device.amapi_device_name}:`, error.message);
    }

    await db.query(
      `UPDATE devices SET status = 'decoupled', amapi_device_name = NULL, amapi_device_id = NULL,
       managed_google_account = NULL, updated_at = NOW() WHERE id = $1`,
      [deviceId]
    );

    await hardwareBindingService.removeHardwareBinding(deviceId);

    await firebaseService.writeDeviceMetadata(deviceId, {
      decoupledAt: new Date().toISOString(),
      decoupledReason: 'Full payment received'
    });

    const signedCommand = await commandSigningService.createAndStoreSignedCommand(
      deviceId,
      'decouple',
      { reason: 'Full payment received' },
      device.imei
    );

    await this.logAuditEvent({
      actor: 'system',
      action: 'DECOUPLE_DEVICE',
      deviceId,
      metadata: { reason: 'Full payment received' },
      result: 'success'
    });

    logger.info(`Device decoupled: ${deviceId}`);

    return {
      deviceId,
      status: 'decoupled',
      decoupledAt: new Date().toISOString()
    };
  }

  async verifyHardwareAndGetDevice(deviceId, imei, serialNumber, socId) {
    const verification = await hardwareBindingService.verifyDeviceHardware(
      deviceId,
      imei,
      serialNumber,
      socId
    );

    if (!verification.isValid) {
      throw new Error('Hardware binding verification failed');
    }

    return this.getDeviceById(deviceId);
  }
}

module.exports = new DeviceService();
