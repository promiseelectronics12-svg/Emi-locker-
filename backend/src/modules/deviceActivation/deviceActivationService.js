const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const { verifyKeySignature } = require('../keys/keyService');

const ACTIVATION_STATUSES = {
  ASSIGNED: 'assigned',
  ACTIVATED: 'activated'
};

function hashValue(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function normalizeIdentifier(value, fallback = null) {
  const normalized = String(value || '').trim();
  return normalized || fallback;
}

function createDeviceToken({ deviceId, dealerId, resellerId }) {
  const secret = process.env.DEVICE_TOKEN_SECRET || process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('DEVICE_TOKEN_SECRET or JWT_SECRET must be configured');
  }

  return jwt.sign(
    {
      sub: deviceId,
      type: 'device',
      dealerId,
      resellerId
    },
    secret,
    { expiresIn: process.env.DEVICE_TOKEN_EXPIRES_IN || '30d' }
  );
}

function getPolicy({ testMode = false } = {}) {
  return {
    locationEnabled: true,
    lockEnabled: true,
    resetEnabled: false,
    frpEnabled: false,
    testMode
  };
}

function shouldAllowTestCode() {
  return String(process.env.DEVICE_ACTIVATION_ALLOW_TEST_CODE || '').toLowerCase() === 'true';
}

async function verifyStagingActivation(payload = {}) {
  const activationCode = normalizeIdentifier(payload.activationCode || payload.activation_code);
  const deviceBoundId = normalizeIdentifier(payload.deviceBoundId || payload.device_bound_id);
  const imei = normalizeIdentifier(payload.imei, deviceBoundId);
  const androidId = normalizeIdentifier(payload.androidId || payload.android_id);
  const serialNumber = normalizeIdentifier(payload.serialNumber || payload.serial_number);
  const socId = normalizeIdentifier(payload.socId || payload.soc_id, deviceBoundId);
  const deviceName = normalizeIdentifier(payload.deviceName || payload.device_name, 'Android device');
  const model = normalizeIdentifier(payload.model);
  const brand = normalizeIdentifier(payload.brand);
  const sdk = normalizeIdentifier(payload.sdk);
  const fcmToken = normalizeIdentifier(payload.fcmToken || payload.fcm_token);

  if (!activationCode || activationCode.length < 6 || activationCode.length > 64) {
    const error = new Error('Invalid activation code');
    error.statusCode = 400;
    throw error;
  }

  if (!deviceBoundId && !imei && !androidId) {
    const error = new Error('Device binding information is required');
    error.statusCode = 400;
    throw error;
  }

  const configuredTestCode = process.env.DEVICE_ACTIVATION_TEST_CODE;
  if (shouldAllowTestCode() && configuredTestCode && activationCode === configuredTestCode) {
    const testDeviceId = `test-${hashValue(deviceBoundId || androidId || imei).slice(0, 24)}`;
    return {
      success: true,
      mode: 'staging-test',
      deviceId: testDeviceId,
      deviceToken: createDeviceToken({
        deviceId: testDeviceId,
        dealerId: 'staging',
        resellerId: 'staging'
      }),
      policy: getPolicy({ testMode: true }),
      message: 'Staging activation verified'
    };
  }

  const client = await db.getClient();

  try {
    await client.query('BEGIN');

    const keyResult = await client.query(
      `SELECT *
       FROM activation_keys
       WHERE key_string = $1
       FOR UPDATE`,
      [activationCode]
    );

    if (keyResult.rows.length === 0) {
      await client.query('ROLLBACK');
      const error = new Error('Activation code not found');
      error.statusCode = 404;
      throw error;
    }

    const key = keyResult.rows[0];
    if (key.status !== ACTIVATION_STATUSES.ASSIGNED || !key.dealer_id) {
      await client.query('ROLLBACK');
      const error = new Error('Activation code is not ready for device activation');
      error.statusCode = 400;
      throw error;
    }

    if (key.activated_at || key.device_id || key.status === ACTIVATION_STATUSES.ACTIVATED) {
      await client.query('ROLLBACK');
      const error = new Error('Activation code already used');
      error.statusCode = 409;
      throw error;
    }

    if (
      key.hmac_signature &&
      key.nonce &&
      key.sig_timestamp &&
      !verifyKeySignature(key.key_string, key.dealer_id, key.sig_timestamp, key.nonce, key.hmac_signature)
    ) {
      await client.query('ROLLBACK');
      const error = new Error('Activation code signature validation failed');
      error.statusCode = 400;
      throw error;
    }

    const imeiHash = hashValue(imei);
    const existingDevice = await client.query(
      `SELECT id
       FROM devices
       WHERE imei_hash = $1 AND COALESCE(status, '') != 'decoupled'
       LIMIT 1`,
      [imeiHash]
    );

    if (existingDevice.rows.length > 0) {
      await client.query('ROLLBACK');
      const error = new Error('Device is already activated');
      error.statusCode = 409;
      throw error;
    }

    const deviceId = uuidv4();
    await client.query(
      `INSERT INTO devices (
        id, imei, imei_hash, serial_number, soc_id, dealer_id, reseller_id,
        activation_key_id, fcm_token, device_name, model, brand, status,
        lock_level, enrolled_at, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'enrolled', 'NONE', NOW(), NOW(), NOW())`,
      [
        deviceId,
        imei,
        imeiHash,
        serialNumber,
        socId,
        key.dealer_id,
        key.reseller_id,
        key.id,
        fcmToken,
        deviceName,
        model,
        brand
      ]
    );

    await client.query(
      `UPDATE activation_keys
       SET status = $1, imei_hash = $2, device_id = $3, activated_at = NOW(), updated_at = NOW()
       WHERE id = $4`,
      [ACTIVATION_STATUSES.ACTIVATED, imeiHash, deviceId, key.id]
    );

    await client.query('COMMIT');

    return {
      success: true,
      mode: 'assigned-key',
      deviceId,
      deviceToken: createDeviceToken({
        deviceId,
        dealerId: key.dealer_id,
        resellerId: key.reseller_id
      }),
      policy: getPolicy(),
      message: 'Device activated successfully'
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      logger.warn('Activation rollback failed:', rollbackError);
    }
    throw error;
  } finally {
    client.release();
  }
}

module.exports = {
  verifyStagingActivation
};
