const crypto = require('crypto');
const db = require('../../config/database');

const KEY_CHARSET = 'ABCDEFGHJKLMNPQRTUVWXYZ2346789';
const KEY_SEGMENTS = 4;
const SEGMENT_LENGTH = 4;
const HMAC_SECRET = process.env.HMAC_SECRET;

if (!HMAC_SECRET) {
  throw new Error('HMAC_SECRET environment variable must be set - key signatures cannot be securely generated without it');
}

async function generateKeyString() {
  let attempts = 0;
  const maxAttempts = 5;
  while (attempts < maxAttempts) {
    const segments = [];
    for (let s = 0; s < KEY_SEGMENTS; s++) {
      let segment = '';
      for (let i = 0; i < SEGMENT_LENGTH; i++) {
        const randomBytes = crypto.randomBytes(4);
        const index = Math.abs(randomBytes.readUInt32BE(0) % KEY_CHARSET.length);
        segment += KEY_CHARSET.charAt(index);
      }
      segments.push(segment);
    }
    const keyString = segments.join('-');
    try {
      const result = await db.query('SELECT id FROM keys WHERE key_string = $1', [keyString]);
      if (result.rows.length === 0) {
        return keyString;
      }
    } catch (err) {
    }
    attempts++;
  }
  throw new Error('Failed to generate unique key after max attempts');
}

function signKey(keyString, dealerId, nonce) {
  const timestamp = Date.now();
  const data = `${keyString}:${dealerId}:${timestamp}:${nonce}`;
  const hmac = crypto.createHmac('sha256', HMAC_SECRET);
  hmac.update(data);
  const signature = hmac.digest('hex');
  return { signature, timestamp };
}

function verifyKeySignature(keyString, dealerId, timestamp, nonce, signature) {
  const data = `${keyString}:${dealerId}:${timestamp}:${nonce}`;
  const hmac = crypto.createHmac('sha256', HMAC_SECRET);
  hmac.update(data);
  const expectedSignature = hmac.digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(signature, 'hex'),
    Buffer.from(expectedSignature, 'hex')
  );
}

function calculateEntropy() {
  const charsetSize = KEY_CHARSET.length;
  const totalChars = KEY_SEGMENTS * SEGMENT_LENGTH;
  const combinations = Math.pow(charsetSize, totalChars);
  return Math.log2(combinations);
}

function isValidKeyFormat(keyString) {
  const pattern = /^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/;
  return pattern.test(keyString);
}

module.exports = {
  generateKeyString,
  signKey,
  verifyKeySignature,
  calculateEntropy,
  isValidKeyFormat,
  KEY_CHARSET,
  KEY_SEGMENTS,
  SEGMENT_LENGTH
};