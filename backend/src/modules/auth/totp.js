const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const speakeasy = require('speakeasy');
const db = require('../../config/database');
const logger = require('../../utils/logger');

const BACKUP_CODE_COUNT = 8;
const ENCRYPTION_PREFIX = 'enc:';

function getEncryptionKey() {
  const source =
    process.env.TOTP_ENCRYPTION_KEY ||
    process.env.JWT_PRIVATE_KEY ||
    process.env.JWT_SECRET ||
    'emi-locker-development-totp-key';

  return crypto.createHash('sha256').update(source).digest();
}

function encryptSecret(secret) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();

  return `${ENCRYPTION_PREFIX}${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
}

function decryptSecret(secret) {
  if (!secret) return null;
  if (!secret.startsWith(ENCRYPTION_PREFIX)) return secret;

  const [, encoded] = secret.split(ENCRYPTION_PREFIX);
  const [ivHex, authTagHex, encryptedHex] = encoded.split(':');
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    getEncryptionKey(),
    Buffer.from(ivHex, 'hex')
  );

  decipher.setAuthTag(Buffer.from(authTagHex, 'hex'));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedHex, 'hex')),
    decipher.final()
  ]);

  return decrypted.toString('utf8');
}

function generateTOTP(email, role) {
  const secret = speakeasy.generateSecret({
    name: `EMI Locker (${role.toUpperCase()}):${email}`,
    issuer: 'EMI Locker',
    length: 20
  });

  return {
    secret: secret.base32,
    otpauthUrl: secret.otpauth_url
  };
}

function verifyTOTP(code, storedSecret) {
  if (!code || !storedSecret) return false;

  const normalizedCode = String(code).replace(/\s/g, '');
  if (!/^\d{6}$/.test(normalizedCode)) {
    return false;
  }

  try {
    return speakeasy.totp.verify({
      secret: decryptSecret(storedSecret),
      encoding: 'base32',
      token: normalizedCode,
      window: 1
    });
  } catch (error) {
    logger.error('TOTP verification failed:', error);
    return false;
  }
}

async function setup(userId, email, role) {
  const { secret, otpauthUrl } = generateTOTP(email, role);
  const encryptedSecret = encryptSecret(secret);

  await db.query(
    'UPDATE users SET totp_secret = $1, totp_pending = $2, updated_at = NOW() WHERE id = $3',
    [encryptedSecret, true, userId]
  );

  return { secret, otpauthUrl };
}

async function verify(userId, token) {
  const result = await db.query('SELECT totp_secret FROM users WHERE id = $1', [userId]);
  if (result.rows.length === 0 || !result.rows[0].totp_secret) {
    return false;
  }

  return verifyTOTP(token, result.rows[0].totp_secret);
}

function normalizeBackupCode(code) {
  return String(code).toUpperCase().replace(/\s/g, '');
}

function generateSingleBackupCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  const bytes = crypto.randomBytes(8);
  let code = '';

  for (let i = 0; i < 8; i += 1) {
    if (i > 0 && i % 4 === 0) {
      code += '-';
    }

    code += chars.charAt(bytes[i] % chars.length);
  }

  return code;
}

async function hashBackupCode(code) {
  return bcrypt.hash(normalizeBackupCode(code), 12);
}

async function generateBackupCodes(userId) {
  const plainCodes = [];
  const hashedCodes = [];

  for (let index = 0; index < BACKUP_CODE_COUNT; index += 1) {
    const code = generateSingleBackupCode();
    plainCodes.push(code);
    hashedCodes.push(await hashBackupCode(code));
  }

  if (userId) {
    await db.query(
      'UPDATE users SET backup_codes = $1, updated_at = NOW() WHERE id = $2',
      [hashedCodes, userId]
    );
  }

  return {
    plain: plainCodes,
    hashed: hashedCodes
  };
}

async function verifyBackupCode(userId, code) {
  const result = await db.query('SELECT backup_codes FROM users WHERE id = $1', [userId]);
  if (result.rows.length === 0) {
    return false;
  }

  const storedCodes = result.rows[0].backup_codes || [];
  const normalizedCode = normalizeBackupCode(code);
  const remainingCodes = [];
  let matched = false;

  for (const storedCode of storedCodes) {
    if (!matched && await bcrypt.compare(normalizedCode, storedCode)) {
      matched = true;
      continue;
    }

    remainingCodes.push(storedCode);
  }

  if (matched) {
    await db.query(
      'UPDATE users SET backup_codes = $1, updated_at = NOW() WHERE id = $2',
      [remainingCodes, userId]
    );
  }

  return matched;
}

module.exports = {
  setup,
  verify,
  generateTOTP,
  verifyTOTP,
  generateBackupCodes,
  generateSingleBackupCode,
  hashBackupCode,
  verifyBackupCode,
  encryptSecret,
  decryptSecret
};
