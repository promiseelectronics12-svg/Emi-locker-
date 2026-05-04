const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');

const PAUT_EXPIRY_HOURS = 48;

class PautService {
  getSigningKey() {
    const key = process.env.PAUT_SIGNING_SECRET;
    if (!key) {
      if (process.env.NODE_ENV === 'production') {
        throw new Error('PAUT_SIGNING_SECRET must be set in production');
      }
      logger.warn('PAUT_SIGNING_SECRET not set, using dev fallback');
      return 'dev-paut-signing-secret-do-not-use';
    }
    return key;
  }

  hashToken(token) {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  async issueToken({ deviceId, imei, lockLevel }) {
    const jti = uuidv4();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + PAUT_EXPIRY_HOURS * 60 * 60;

    const payload = {
      jti,
      sub: deviceId,
      imei,
      lockLevel: lockLevel || 'FULL_LOCK',
      purpose: 'PRE_AUTHORIZED_UNLOCK',
      iat: now,
      exp,
    };

    const token = jwt.sign(payload, this.getSigningKey(), { algorithm: 'HS256' });
    const tokenHash = this.hashToken(token);

    await db.query(
      `INSERT INTO paut_tokens (jti, device_id, imei, lock_level, token_hash, issued_at, expires_at, used, created_at)
       VALUES ($1, $2, $3, $4, $5, to_timestamp($6), to_timestamp($7), false, NOW())`,
      [jti, deviceId, imei, lockLevel || 'FULL_LOCK', tokenHash, now, exp]
    );

    logger.info('PAUT token issued', { jti, deviceId, expiresAt: new Date(exp * 1000).toISOString() });

    return {
      token,
      jti,
      deviceId,
      imei,
      lockLevel: lockLevel || 'FULL_LOCK',
      issuedAt: new Date(now * 1000).toISOString(),
      expiresAt: new Date(exp * 1000).toISOString(),
    };
  }

  async verifyToken(token) {
    try {
      const decoded = jwt.verify(token, this.getSigningKey(), { algorithms: ['HS256'] });

      const dbToken = await db.query(
        `SELECT * FROM paut_tokens WHERE jti = $1`,
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
        purpose: 'PRE_AUTHORIZED_UNLOCK',
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
      `UPDATE paut_tokens SET used = true, used_at = NOW() WHERE jti = $1 AND used = false RETURNING *`,
      [jti]
    );

    if (result.rows.length === 0) {
      return { consumed: false, reason: 'Token not found or already consumed' };
    }

    logger.info('PAUT token consumed', { jti });
    return { consumed: true, token: result.rows[0] };
  }

  async revokeToken(jti) {
    await db.query(
      `UPDATE paut_tokens SET revoked = true, revoked_at = NOW() WHERE jti = $1`,
      [jti]
    );
    logger.info('PAUT token revoked', { jti });
  }

  async revokeAllForDevice(deviceId) {
    await db.query(
      `UPDATE paut_tokens SET revoked = true, revoked_at = NOW() WHERE device_id = $1 AND used = false`,
      [deviceId]
    );
    logger.info('All PAUT tokens revoked for device', { deviceId });
  }
}

module.exports = new PautService();
