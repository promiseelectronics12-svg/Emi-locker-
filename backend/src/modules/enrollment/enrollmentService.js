const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const { emitEnrollmentComplete } = require('../sse/sseService');

function generateSixDigitToken() {
  return String(crypto.randomInt(100000, 999999));
}

/**
 * Dealer submits customer + device info.
 * Server generates a 6-digit code, stores its hash, and returns the
 * plaintext code directly to the dealer app to show on screen.
 * No FCM involved — dealer physically types the code into the user app.
 */
async function startEnrollment({ dealerId, customer_name, nid_hash, phone_number, brand, model, imei1, imei2 }) {
  const deviceRow = await db.query(
    `SELECT id, status FROM devices WHERE imei = $1 LIMIT 1`,
    [imei1]
  );

  if (!deviceRow.rows.length) {
    const err = new Error('Device not found. The customer must open the SIM Toolkit app on their device first.');
    err.statusCode = 404;
    throw err;
  }

  const device = deviceRow.rows[0];

  if (device.status === 'enrolled' || device.status === 'active') {
    const err = new Error('This device is already enrolled.');
    err.statusCode = 409;
    throw err;
  }

  const token = generateSixDigitToken();
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const enrollmentId = uuidv4();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

  await db.query(
    `INSERT INTO enrollments
       (id, device_id, dealer_id, customer_name, nid_hash, phone_number,
        brand, model, imei1, imei2, token_hash, status, expires_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'pending',$12,NOW())`,
    [enrollmentId, device.id, dealerId, customer_name, nid_hash, phone_number,
     brand, model, imei1, imei2 || null, tokenHash, expiresAt]
  );

  logger.info('Enrollment started', { enrollmentId, imei: imei1.slice(-4) });

  // Return plaintext token to dealer app — dealer will type it into the user app
  return { enrollment_id: enrollmentId, token };
}

/**
 * Called by the USER APP (not the dealer app).
 * User app reads real IMEI from device hardware and sends it with the code
 * the dealer typed in. Server verifies both match → binding confirmed.
 */
async function confirmFromDevice({ code, imei }) {
  const tokenHash = crypto.createHash('sha256').update(String(code)).digest('hex');

  // Find a pending enrollment matching this IMEI and code hash
  const row = await db.query(
    `SELECT e.*, d.id AS dev_id
     FROM enrollments e
     JOIN devices d ON d.id = e.device_id
     WHERE e.imei1 = $1
       AND e.token_hash = $2
       AND e.status = 'pending'
       AND e.expires_at > NOW()
     LIMIT 1`,
    [imei, tokenHash]
  );

  if (!row.rows.length) {
    // Give a generic message — don't reveal whether IMEI or code was wrong
    const err = new Error('Code is incorrect or has expired. Ask your dealer to try again.');
    err.statusCode = 422;
    throw err;
  }

  const enrollment = row.rows[0];

  await db.query(
    `UPDATE devices
     SET status     = 'enrolled',
         brand      = $2,
         model      = $3,
         dealer_id  = $4,
         updated_at = NOW()
     WHERE id = $1`,
    [enrollment.dev_id, enrollment.brand, enrollment.model, enrollment.dealer_id]
  );

  await db.query(
    `UPDATE enrollments SET status = 'confirmed', confirmed_at = NOW() WHERE id = $1`,
    [enrollment.id]
  );

  logger.info('Device bound via user app', { enrollmentId: enrollment.id, imei: imei.slice(-4) });

  try {
    const devRow = await db.query(`SELECT id, device_name, imei FROM devices WHERE id = $1`, [enrollment.dev_id]);
    if (devRow.rows.length) emitEnrollmentComplete(devRow.rows[0], enrollment.dealer_id);
  } catch (_) {}

  return { success: true, device_id: enrollment.dev_id };
}

module.exports = { startEnrollment, confirmFromDevice };
