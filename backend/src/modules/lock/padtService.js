const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');

const PADT_EXPIRY_DAYS = 7;

class PadtService {
  getSigningKey() {
    const key = process.env.PADT_SIGNING_SECRET;
    if (!key) {
      if (process.env.NODE_ENV === 'production') {
        throw new Error('PADT_SIGNING_SECRET must be set in production');
      }
      logger.warn('PADT_SIGNING_SECRET not set, using dev fallback');
      return 'dev-padt-signing-secret-do-not-use';
    }
    return key;
  }

  hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  async issueToken({ deviceId, imei, ownerId, dealerId }) {
    const jti = uuidv4();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + PADT_EXPIRY_DAYS * 24 * 60 * 60;

    const payload = {
      jti,
      sub: deviceId,
      imei,
      ownerId: ownerId || null,
      dealerId: dealerId || null,
      purpose: 'PRE_AUTHORIZED_DECOUPLE',
      iat: now,
      exp,
    };

    const token = jwt.sign(payload, this.getSigningKey(), { algorithm: 'HS256' });
    const tokenHash = this.hashToken(token);

    await db.query(
      `INSERT INTO padt_tokens (jti, device_id, imei, owner_id, dealer_id, token_hash, issued_at, expires_at, used, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, to_timestamp($7), to_timestamp($8), false, NOW())`,
      [jti, deviceId, imei, ownerId || null, dealerId || null, tokenHash, now, exp]
    );

    logger.info('PADT token issued', { jti, deviceId, expiresAt: new Date(exp * 1000).toISOString() });

    return {
      token,
      jti,
      deviceId,
      imei,
      issuedAt: new Date(now * 1000).toISOString(),
      expiresAt: new Date(exp * 1000).toISOString(),
    };
  }

  async verifyToken(token) {
    try {
      const decoded = jwt.verify(token, this.getSigningKey(), { algorithms: ['HS256'] });

      const dbToken = await db.query(
        `SELECT * FROM padt_tokens WHERE jti = $1`,
        [decoded.jti]
      );

      if (dbToken.rows.length === 0) {
        return { valid: false, reason: 'Token not found in database' };
      }

      const record = dbToken.rows[0];

      if (record.used) {
        return { valid: false, reason: 'Token already consumed' };
      }

      if (record.revoked) {
        return { valid: false, reason: 'Token has been revoked' };
      }

      if (new Date(record.expires_at) < new Date()) {
        return { valid: false, reason: 'Token expired' };
      }

      return {
        valid: true,
        expiresAt: record.expires_at,
        purpose: 'PRE_AUTHORIZED_DECOUPLE',
      };
    } catch (error) {
      if (error.name === 'TokenExpiredError') {
        return { valid: false, reason: 'Token expired' };
      }
      return { valid: false, reason: `Token verification failed: ${error.message}` };
    }
  }

  async verifyAndConsumeToken(token) {
    const verifyResult = await this.verifyToken(token);
    if (!verifyResult.valid) {
      return { consumed: false, reason: verifyResult.reason };
    }

    try {
      const decoded = jwt.verify(token, this.getSigningKey(), { algorithms: ['HS256'] });
      return await this.consumeToken(decoded.jti);
    } catch (error) {
      return { consumed: false, reason: `Token verification failed: ${error.message}` };
    }
  }

  async consumeToken(jti) {
    const result = await db.query(
      `UPDATE padt_tokens SET used = true, used_at = NOW() WHERE jti = $1 AND used = false AND revoked = false RETURNING *`,
      [jti]
    );

    if (result.rows.length === 0) {
      return { consumed: false, reason: 'Token not found, already consumed, or revoked' };
    }

    logger.info('PADT token consumed', { jti });
    return { consumed: true, token: result.rows[0] };
  }

  async revokeToken(jti) {
    await db.query(
      `UPDATE padt_tokens SET revoked = true, revoked_at = NOW() WHERE jti = $1`,
      [jti]
    );
    logger.info('PADT token revoked', { jti });
  }

  async revokeAllForDevice(deviceId) {
    await db.query(
      `UPDATE padt_tokens SET revoked = true, revoked_at = NOW() WHERE device_id = $1 AND used = false`,
      [deviceId]
    );
    logger.info('All PADT tokens revoked for device', { deviceId });
  }
}

module.exports = new PadtService();
