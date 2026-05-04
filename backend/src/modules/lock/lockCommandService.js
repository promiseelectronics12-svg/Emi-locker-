const crypto = require('crypto');
const redis = require('../../config/redis');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const kmsSigningService = require('../devices/kmsSigningService');

const NONCE_EXPIRY_SECONDS = 300;
const COMMAND_EXPIRY_MS = 5 * 60 * 1000;

class LockCommandService {
  generateNonce() {
    return crypto.randomBytes(16).toString('hex');
  }

  async isNonceUsed(nonce) {
    const existing = await redis.get(`lock:nonce:${nonce}`);
    return existing !== null;
  }

  async storeNonce(nonce) {
    await redis.setex(`lock:nonce:${nonce}`, NONCE_EXPIRY_SECONDS, '1');
  }

  async generateSignedCommand({ deviceImei, actionType, lockLevel, metadata = {} }) {
    const nonce = this.generateNonce();
    const timestamp = Date.now();

    const nonceUsed = await this.isNonceUsed(nonce);
    if (nonceUsed) {
      throw new Error('Nonce collision — retry');
    }

    const payload = {
      deviceImei,
      timestamp,
      nonce,
      actionType,
      lockLevel: lockLevel || null,
      metadata,
    };

    const signatureResult = await kmsSigningService.sign(payload);

    const command = {
      ...payload,
      hmacSignature: signatureResult.signature,
      signatureProvider: signatureResult.provider,
      signatureKeyId: signatureResult.keyId,
      expiresAt: new Date(timestamp + COMMAND_EXPIRY_MS).toISOString(),
    };

    await this.storeNonce(nonce);

    logger.info('Signed lock command generated', {
      deviceImei,
      actionType,
      nonce,
      signatureProvider: signatureResult.provider,
      expiresAt: command.expiresAt,
    });

    return command;
  }

  async verifyCommand(command) {
    const { deviceImei, timestamp, nonce, actionType, lockLevel, metadata, hmacSignature } = command;

    if (!hmacSignature) {
      await this.logSecurityEvent('MISSING_SIGNATURE', { deviceImei, actionType, timestamp });
      return { valid: false, reason: 'Missing signature' };
    }

    const age = Date.now() - timestamp;
    if (age > COMMAND_EXPIRY_MS || age < 0) {
      await this.logSecurityEvent('EXPIRED_COMMAND', { deviceImei, actionType, age });
      return { valid: false, reason: 'Command expired or invalid timestamp' };
    }

    const payload = { deviceImei, timestamp, nonce, actionType, lockLevel, metadata };
    const isValid = await kmsSigningService.verifySignature(payload, hmacSignature, {
      provider: command.signatureProvider,
      keyId: command.signatureKeyId,
    });

    if (!isValid) {
      await this.logSecurityEvent('INVALID_SIGNATURE', { deviceImei, actionType, timestamp });
      return { valid: false, reason: 'Signature mismatch' };
    }

    return { valid: true };
  }

  async logSecurityEvent(eventType, metadata) {
    try {
      await db.query(
        `INSERT INTO security_events (event_type, severity, metadata, created_at)
         VALUES ($1, $2, $3, NOW())`,
        [eventType, 'warning', JSON.stringify(metadata)]
      );
    } catch (error) {
      logger.error('Failed to log security event:', error);
    }
  }

  async verifyAndConsumeNonce(command) {
    const { nonce } = command;
    const key = `lock:nonce:${nonce}`;
    const exists = await redis.get(key);
    if (exists) {
      await redis.del(key);
      return true;
    }
    return false;
  }
}

module.exports = new LockCommandService();
