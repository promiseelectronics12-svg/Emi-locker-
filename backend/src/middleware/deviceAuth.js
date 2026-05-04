const crypto = require('crypto');
const db = require('../config/database');
const redis = require('../config/redis');
const logger = require('../utils/logger');

const DEVICE_SIGNATURE_MAX_AGE_MS = 5 * 60 * 1000;
const COMMAND_SIGNATURE_MAX_AGE_MS = 5 * 60 * 1000;
const COMMAND_NONCE_TTL_SECONDS = 5 * 60;

function standardError(res, status, code, message) {
  return res.status(status).json({
    status: 'error',
    code,
    message
  });
}

function safeJson(value) {
  return JSON.stringify(value || {});
}

function getBodyHash(body) {
  return crypto.createHash('sha256').update(safeJson(body)).digest('hex');
}

function validateHexSignature(actual, expected) {
  const actualBuffer = Buffer.from(actual, 'hex');
  const expectedBuffer = Buffer.from(expected, 'hex');

  if (actualBuffer.length !== expectedBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(actualBuffer, expectedBuffer);
}

async function authenticateDevice(req, res, next) {
  const imei = req.headers['x-device-imei'];
  const deviceSignature = req.headers['x-device-signature'];
  const deviceTimestamp = req.headers['x-device-timestamp'];

  if (!imei || !deviceSignature || !deviceTimestamp) {
    return standardError(res, 401, 'DEVICE_CREDENTIALS_REQUIRED', 'Device credentials required');
  }

  const age = Date.now() - parseInt(deviceTimestamp, 10);
  if (Number.isNaN(age) || age > DEVICE_SIGNATURE_MAX_AGE_MS || age < 0) {
    return standardError(res, 401, 'DEVICE_SIGNATURE_EXPIRED', 'Device signature expired');
  }

  try {
    const result = await db.query(
      `SELECT id, imei, model, brand, fcm_token, status, dealer_id, owner_id
       FROM devices
       WHERE imei = $1`,
      [imei]
    );

    if (result.rows.length === 0) {
      return standardError(res, 401, 'DEVICE_NOT_FOUND', 'Device not found');
    }

    const device = result.rows[0];
    const secret = process.env.DEVICE_SIGNING_SECRET;
    if (!secret) {
      throw new Error('DEVICE_SIGNING_SECRET is not configured');
    }

    const bodyHash = getBodyHash(req.body);
    const signatureData = `${device.id}:${deviceTimestamp}:${bodyHash}`;
    const expectedSignature = crypto.createHmac('sha256', secret).update(signatureData).digest('hex');

    if (!validateHexSignature(deviceSignature, expectedSignature)) {
      return standardError(res, 401, 'INVALID_DEVICE_SIGNATURE', 'Invalid device signature');
    }

    req.device = {
      id: device.id,
      imei: device.imei,
      model: device.model,
      brand: device.brand,
      dealerId: device.dealer_id,
      ownerId: device.owner_id
    };

    return next();
  } catch (error) {
    logger.error('Device authentication error:', error);
    return standardError(res, 401, 'DEVICE_AUTHENTICATION_FAILED', 'Device authentication failed');
  }
}

async function validateSignedDeviceCommand(req, res, next) {
  const timestamp = req.headers['x-command-timestamp'];
  const nonce = req.headers['x-command-nonce'];
  const signature = req.headers['x-command-signature'];

  if (!timestamp || !nonce || !signature) {
    return standardError(res, 401, 'COMMAND_SIGNATURE_REQUIRED', 'Signed command headers are required');
  }

  const age = Date.now() - parseInt(timestamp, 10);
  if (Number.isNaN(age) || age > COMMAND_SIGNATURE_MAX_AGE_MS || age < 0) {
    return standardError(res, 401, 'COMMAND_SIGNATURE_EXPIRED', 'Command signature expired');
  }

  const secret = process.env.LOCK_COMMAND_SIGNING_SECRET;
  if (!secret) {
    logger.error('LOCK_COMMAND_SIGNING_SECRET must be set');
    return standardError(res, 500, 'COMMAND_SIGNING_NOT_CONFIGURED', 'Command signing is not configured');
  }

  const nonceKey = `command_nonce:${nonce}`;
  const alreadyUsed = await redis.exists(nonceKey);
  if (alreadyUsed) {
    return standardError(res, 401, 'COMMAND_REPLAY_DETECTED', 'Command nonce has already been used');
  }

  try {
    const deviceId = req.params.id || req.body.deviceId || req.body.device_id;
    const deviceResult = deviceId
      ? await db.query('SELECT id, imei FROM devices WHERE id = $1', [deviceId])
      : null;

    const headerImei = req.headers['x-device-imei'] || req.body.imei || req.body.deviceImei;
    const imei = deviceResult?.rows?.[0]?.imei || headerImei;

    if (!imei) {
      return standardError(res, 400, 'DEVICE_IMEI_REQUIRED', 'Device IMEI is required for command signing');
    }

    const bodyHash = getBodyHash(req.body);
    const signaturePayload = `${imei}:${timestamp}:${nonce}:${bodyHash}`;
    const expectedSignature = crypto.createHmac('sha256', secret).update(signaturePayload).digest('hex');

    if (!validateHexSignature(signature, expectedSignature)) {
      return standardError(res, 401, 'INVALID_COMMAND_SIGNATURE', 'Invalid command signature');
    }

    await redis.setex(nonceKey, COMMAND_NONCE_TTL_SECONDS, '1');
    req.commandSignature = { imei, nonce, timestamp };

    return next();
  } catch (error) {
    logger.error('Command signing validation error:', error);
    return standardError(res, 401, 'COMMAND_SIGNATURE_VALIDATION_FAILED', 'Command signature validation failed');
  }
}

module.exports = {
  authenticateDevice,
  validateSignedDeviceCommand
};
