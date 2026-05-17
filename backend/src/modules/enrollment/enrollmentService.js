const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const { emitEnrollmentComplete } = require('../sse/sseService');
const assignmentService = require('../assignments/assignmentService');
const { hashNid, normalizeNid } = require('../../utils/nidUtils');

function createDeviceToken({ deviceId, dealerId, resellerId }) {
  const secret = process.env.DEVICE_TOKEN_SECRET;
  if (!secret) throw new Error('DEVICE_TOKEN_SECRET must be set — must not share signing secret with user JWTs');
  return jwt.sign({ sub: deviceId, type: 'device', dealerId, resellerId }, secret, {
    expiresIn: process.env.DEVICE_TOKEN_EXPIRES_IN || '30d'
  });
}

function createOfflineUnlockSecret() {
  return crypto.randomBytes(20).toString('base64');
}

function createCustomerEmail({ nidHash, phoneNumber }) {
  const fingerprint = crypto
    .createHash('sha256')
    .update(`${nidHash || ''}:${phoneNumber || ''}`)
    .digest('hex')
    .slice(0, 20);
  return `customer.${fingerprint}@emi-locker.local`;
}

function truncateNullable(value, maxLength) {
  if (value === undefined || value === null) return null;
  return String(value).slice(0, maxLength);
}

function normalizeImei(value) {
  return String(value || '').replace(/\D/g, '');
}

function generateSixDigitToken() {
  return String(crypto.randomInt(100000, 999999));
}

function normalizeEmiTerms({
  totalAmount,
  downPayment,
  emiAmount,
  duration,
  startDate,
  graceDays
}) {
  const total = Number(totalAmount);
  const down = Number(downPayment);
  const monthly = Number(emiAmount);
  const months = Number.parseInt(duration, 10);
  const grace =
    graceDays === undefined || graceDays === null || graceDays === ''
      ? 7
      : Number.parseInt(graceDays, 10);

  if (!Number.isFinite(total) || total <= 0) throw new Error('Total amount must be positive.');
  if (!Number.isFinite(down) || down < 0) throw new Error('Down payment must be zero or more.');
  if (!Number.isFinite(monthly) || monthly <= 0)
    throw new Error('Monthly EMI amount must be positive.');
  if (!Number.isInteger(months) || months < 1 || months > 60)
    throw new Error('Duration must be 1-60 months.');
  if (!Number.isInteger(grace) || grace < 0 || grace > 30)
    throw new Error('Grace days must be 0-30.');
  if (!startDate || Number.isNaN(new Date(startDate).getTime()))
    throw new Error('Start date is required.');

  const expected = down + monthly * months;
  if (Math.abs(expected - total) > 0.01) {
    const err = new Error(
      `Total amount must equal down payment + monthly EMI × duration (${expected.toFixed(2)}).`
    );
    err.statusCode = 400;
    throw err;
  }

  return {
    totalAmount: total.toFixed(2),
    downPayment: down.toFixed(2),
    emiAmount: monthly.toFixed(2),
    duration: months,
    startDate: new Date(startDate).toISOString().slice(0, 10),
    graceDays: grace
  };
}

function hasCompleteEmiTerms(payload = {}) {
  return (
    payload.totalAmount !== undefined &&
    payload.totalAmount !== null &&
    payload.emiAmount !== undefined &&
    payload.emiAmount !== null &&
    payload.duration !== undefined &&
    payload.duration !== null &&
    payload.startDate !== undefined &&
    payload.startDate !== null
  );
}

async function upsertActiveSchedule(client, deviceId, emiTerms) {
  const existing = await client.query(
    `SELECT id
     FROM emi_schedules
     WHERE device_id = $1 AND status = 'active'
     ORDER BY created_at DESC
     LIMIT 1
     FOR UPDATE`,
    [deviceId]
  );

  if (existing.rows.length) {
    const updated = await client.query(
      `UPDATE emi_schedules
       SET total_amount = $2,
           down_payment = $3,
           emi_amount = $4,
           duration = $5,
           start_date = $6,
           grace_days = $7,
           updated_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [
        existing.rows[0].id,
        emiTerms.totalAmount,
        emiTerms.downPayment,
        emiTerms.emiAmount,
        emiTerms.duration,
        emiTerms.startDate,
        emiTerms.graceDays
      ]
    );
    return updated.rows[0];
  }

  const created = await client.query(
    `INSERT INTO emi_schedules
       (device_id, total_amount, down_payment, emi_amount, duration, start_date, grace_days, status, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'active', NOW(), NOW())
     RETURNING *`,
    [
      deviceId,
      emiTerms.totalAmount,
      emiTerms.downPayment,
      emiTerms.emiAmount,
      emiTerms.duration,
      emiTerms.startDate,
      emiTerms.graceDays
    ]
  );
  return created.rows[0];
}

function addMonths(date, months) {
  const result = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const originalDay = result.getUTCDate();
  result.setUTCMonth(result.getUTCMonth() + months);
  if (result.getUTCDate() !== originalDay) result.setUTCDate(0);
  return result;
}

function buildInstallments(schedule) {
  const startDate =
    schedule.start_date instanceof Date
      ? schedule.start_date.toISOString().slice(0, 10)
      : String(schedule.start_date).slice(0, 10);
  const start = new Date(`${startDate}T00:00:00.000Z`);
  const duration = Number(schedule.duration) || 0;
  const amount = Number(schedule.emi_amount) || 0;
  return Array.from({ length: duration }, (_, index) => ({
    installmentNumber: index + 1,
    dueDate: addMonths(start, index).toISOString().slice(0, 10),
    amount,
    status: 'PENDING'
  }));
}

function formatSchedule(schedule) {
  if (!schedule) return null;
  return {
    id: schedule.id,
    totalAmount: Number(schedule.total_amount),
    downPayment: Number(schedule.down_payment || 0),
    emiAmount: Number(schedule.emi_amount),
    duration: Number(schedule.duration),
    startDate:
      schedule.start_date instanceof Date
        ? schedule.start_date.toISOString().slice(0, 10)
        : String(schedule.start_date).slice(0, 10),
    graceDays: Number(schedule.grace_days || 0),
    status: schedule.status,
    installments: buildInstallments(schedule)
  };
}

async function resolveDealerIdentity(dealerId, client = db) {
  const result = await client.query(
    `SELECT id, user_id, reseller_id
     FROM dealers
     WHERE id = $1 OR user_id = $1
     LIMIT 1`,
    [dealerId]
  );

  const dealer = result.rows[0];
  const dealerRecordId = dealer?.id || dealerId;
  const dealerUserId = dealer?.user_id || dealerId;

  return {
    dealerRecordId,
    dealerUserId,
    resellerId: dealer?.reseller_id || null,
    keyDealerIds: [...new Set([dealerRecordId, dealerUserId].filter(Boolean))]
  };
}

/**
 * Dealer submits customer + device info.
 * Server generates a 6-digit code, stores its hash, and returns the
 * plaintext code directly to the dealer app to show on screen.
 * No FCM involved — dealer physically types the code into the user app.
 */
async function startEnrollment({
  dealerId,
  customer_name,
  nid,
  phone_number,
  brand,
  model,
  imei1,
  imei2,
  tier,
  totalAmount,
  downPayment,
  emiAmount,
  duration,
  startDate,
  graceDays
}) {
  const primaryImei = normalizeImei(imei1);
  const secondaryImei = normalizeImei(imei2);
  if (secondaryImei && primaryImei === secondaryImei) {
    const err = new Error('IMEI 2 must be different from IMEI 1.');
    err.statusCode = 400;
    throw err;
  }

  const keyTier = ['standard', 'premium', 'vip'].includes(tier) ? tier : 'standard';
  const emiTerms = hasCompleteEmiTerms({ totalAmount, emiAmount, duration, startDate })
    ? normalizeEmiTerms({
        totalAmount,
        downPayment,
        emiAmount,
        duration,
        startDate,
        graceDays
      })
    : null;
  const dealerIdentity = await resolveDealerIdentity(dealerId);

  const stockRow = await db.query(
    `SELECT id
     FROM activation_keys
     WHERE dealer_id = ANY($1::uuid[])
       AND tier = $2
       AND status = 'assigned'
       AND device_id IS NULL
     LIMIT 1`,
    [dealerIdentity.keyDealerIds, keyTier]
  );

  if (!stockRow.rows.length) {
    const err = new Error(`No ready ${keyTier} activation code available for this dealer.`);
    err.statusCode = 409;
    throw err;
  }

  const deviceRow = primaryImei
    ? await db.query(`SELECT id, status FROM devices WHERE imei = $1 LIMIT 1`, [primaryImei])
    : { rows: [] };

  let device;
  if (!deviceRow.rows.length) {
    // Device has not pre-registered yet (Android 10+ blocks IMEI reading for non-system apps).
    // Dealer knows the IMEI from the box — create the record now so binding can proceed.
    const created = await db.query(
      `INSERT INTO devices (imei, brand, model, status, created_at, updated_at)
       VALUES ($1, $2, $3, 'pending', NOW(), NOW())
       RETURNING id, status`,
      [primaryImei || null, brand || null, model || null]
    );
    [device] = created.rows;
    logger.info('Device created by dealer during enrollment', {
      imei: primaryImei ? primaryImei.slice(-4) : null
    });
  } else {
    [device] = deviceRow.rows;
  }

  if (device.status === 'enrolled' || device.status === 'active') {
    const err = new Error('This device is already enrolled.');
    err.statusCode = 409;
    throw err;
  }

  const token = generateSixDigitToken();
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const enrollmentId = uuidv4();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 minutes

  // Compute both hashes from raw NID
  // nid_hash: plain SHA-256 for legacy compat (version 1 behavior retained)
  // nidHmac: HMAC-SHA256 keyed with NID_PLATFORM_SECRET (version 2)
  const normalizedNid = normalizeNid(nid);
  const nid_hash = normalizedNid
    ? crypto.createHash('sha256').update(normalizedNid).digest('hex')
    : null;
  let nidHmac = null;
  try {
    if (normalizedNid) nidHmac = hashNid(normalizedNid);
  } catch (_) {}

  await db.query(
    `INSERT INTO enrollments
       (id, device_id, dealer_id, customer_name, nid_hash, nid_hmac, nid_hash_version,
        phone_number, brand, model, imei1, imei2, token_hash, tier,
        total_amount, down_payment, emi_amount, duration, start_date, grace_days,
        status, expires_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,'pending',$21,NOW())`,
    [
      enrollmentId,
      device.id,
      dealerIdentity.dealerRecordId,
      customer_name,
      nid_hash,
      nidHmac,
      nidHmac ? 2 : 1,
      phone_number,
      brand || null,
      model || null,
      primaryImei || null,
      secondaryImei || null,
      tokenHash,
      keyTier,
      emiTerms?.totalAmount || null,
      emiTerms?.downPayment || null,
      emiTerms?.emiAmount || null,
      emiTerms?.duration || null,
      emiTerms?.startDate || null,
      emiTerms?.graceDays ?? null,
      expiresAt
    ]
  );

  logger.info('Enrollment started', { enrollmentId, imei: primaryImei ? primaryImei.slice(-4) : null });

  // Return plaintext token to dealer app — dealer will type it into the user app
  return { enrollment_id: enrollmentId, device_id: device.id, token };
}

async function getDealerEnrollment(client, dealerIdentity, enrollmentId) {
  const result = await client.query(
    `SELECT e.*, d.id AS dev_id
     FROM enrollments e
     JOIN devices d ON d.id = e.device_id
     WHERE e.id = $1
       AND e.dealer_id = ANY($2::uuid[])
     LIMIT 1
     FOR UPDATE OF e`,
    [enrollmentId, dealerIdentity.keyDealerIds]
  );

  if (!result.rows.length) {
    const err = new Error('Enrollment not found.');
    err.statusCode = 404;
    throw err;
  }
  return result.rows[0];
}

async function saveEnrollmentEmiTerms({
  dealerId,
  enrollmentId,
  totalAmount,
  downPayment,
  emiAmount,
  duration,
  startDate,
  graceDays
}) {
  const emiTerms = normalizeEmiTerms({
    totalAmount,
    downPayment,
    emiAmount,
    duration,
    startDate,
    graceDays
  });
  const dealerIdentity = await resolveDealerIdentity(dealerId);
  const client = await db.getClient();
  let enrollment;
  let schedule = null;

  try {
    await client.query('BEGIN');
    enrollment = await getDealerEnrollment(client, dealerIdentity, enrollmentId);

    const updated = await client.query(
      `UPDATE enrollments
       SET total_amount = $2,
           down_payment = $3,
           emi_amount = $4,
           duration = $5,
           start_date = $6,
           grace_days = $7
       WHERE id = $1
       RETURNING *`,
      [
        enrollment.id,
        emiTerms.totalAmount,
        emiTerms.downPayment,
        emiTerms.emiAmount,
        emiTerms.duration,
        emiTerms.startDate,
        emiTerms.graceDays
      ]
    );
    [enrollment] = updated.rows;

    if (enrollment.status === 'confirmed') {
      schedule = await upsertActiveSchedule(client, enrollment.device_id, emiTerms);
    }

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  return {
    success: true,
    enrollment_id: enrollment.id,
    device_id: enrollment.device_id,
    emi_schedule: formatSchedule(schedule)
  };
}

async function saveEnrollmentDeviceFallback({ dealerId, enrollmentId, brand, model, imei1, imei2 }) {
  const primaryImei = normalizeImei(imei1);
  const secondaryImei = normalizeImei(imei2);
  if (secondaryImei && primaryImei && primaryImei === secondaryImei) {
    const err = new Error('IMEI 2 must be different from IMEI 1.');
    err.statusCode = 400;
    throw err;
  }

  const dealerIdentity = await resolveDealerIdentity(dealerId);
  const client = await db.getClient();
  let enrollment;

  try {
    await client.query('BEGIN');
    enrollment = await getDealerEnrollment(client, dealerIdentity, enrollmentId);

    if (primaryImei) {
      const existing = await client.query(
        `SELECT id, status
         FROM devices
         WHERE imei = $1 AND id <> $2
         LIMIT 1
         FOR UPDATE`,
        [primaryImei, enrollment.device_id]
      );
      if (
        existing.rows.length &&
        !['decoupled', 'pending', 'pending_decouple'].includes(existing.rows[0].status)
      ) {
        const err = new Error('This IMEI is already attached to another active device.');
        err.statusCode = 409;
        throw err;
      }
      if (existing.rows.length) {
        await client.query(`UPDATE enrollments SET device_id = $2 WHERE id = $1`, [
          enrollment.id,
          existing.rows[0].id
        ]);
        await client.query(
          `DELETE FROM devices
           WHERE id = $1 AND imei IS NULL AND owner_id IS NULL AND status = 'pending'`,
          [enrollment.device_id]
        );
        enrollment.device_id = existing.rows[0].id;
      }
    }

    const updated = await client.query(
      `UPDATE enrollments
       SET brand = COALESCE($2, brand),
           model = COALESCE($3, model),
           imei1 = COALESCE($4, imei1),
           imei2 = COALESCE($5, imei2)
       WHERE id = $1
       RETURNING *`,
      [
        enrollment.id,
        truncateNullable(brand, 64),
        truncateNullable(model, 64),
        primaryImei || null,
        secondaryImei || null
      ]
    );
    [enrollment] = updated.rows;

    await client.query(
      `UPDATE devices
       SET imei = COALESCE($2, imei),
           brand = COALESCE($3, brand),
           model = COALESCE($4, model),
           device_name = COALESCE(device_name, NULLIF(CONCAT_WS(' ', $3::text, $4::text), '')),
           updated_at = NOW()
       WHERE id = $1`,
      [
        enrollment.device_id,
        primaryImei || null,
        truncateNullable(brand, 64),
        truncateNullable(model, 64)
      ]
    );

    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }

  return { success: true, enrollment_id: enrollment.id, device_id: enrollment.device_id };
}

/**
 * Called by the USER APP (not the dealer app).
 * User app reads real IMEI from device hardware and sends it with the code
 * the dealer typed in. Server verifies both match → binding confirmed.
 */
async function confirmFromDevice({ code, imei, androidId, deviceBoundId, brand, model }) {
  const tokenHash = crypto.createHash('sha256').update(String(code)).digest('hex');

  // On Android 10+ most apps cannot read IMEI without system privilege.
  // Prefer code + IMEI. If IMEI is unavailable, use the Android/device-bound
  // identifier captured during pre-registration before falling back to code-only.
  let row;
  if (imei) {
    row = await db.query(
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
  }

  if ((!row || !row.rows.length) && (androidId || deviceBoundId)) {
    row = await db.query(
      `SELECT e.*, d.id AS dev_id
       FROM enrollments e
       JOIN devices d ON d.id = e.device_id
       WHERE e.token_hash = $1
         AND e.status = 'pending'
         AND e.expires_at > NOW()
         AND (
           ($2::text IS NOT NULL AND d.android_id = $2)
           OR ($3::text IS NOT NULL AND d.device_bound_id = $3)
         )
       ORDER BY e.created_at DESC
       LIMIT 1`,
      [tokenHash, androidId || null, deviceBoundId || null]
    );
  }

  // Compatibility fallback for already-created enrollments where the device did
  // not pre-register yet. This should become unnecessary once the split flow is
  // fully implemented.
  if (!row || !row.rows.length) {
    row = await db.query(
      `SELECT e.*, d.id AS dev_id
       FROM enrollments e
       JOIN devices d ON d.id = e.device_id
       WHERE e.token_hash = $1
         AND e.status = 'pending'
         AND e.expires_at > NOW()
       ORDER BY e.created_at DESC
       LIMIT 1`,
      [tokenHash]
    );
  }

  if (!row.rows.length) {
    const err = new Error('Code is incorrect or has expired. Ask your dealer to try again.');
    err.statusCode = 422;
    throw err;
  }

  const enrollment = row.rows[0];
  const client = await db.getClient();
  let committedEnrollment;
  let committedDealerIdentity;
  let consumedKey;
  let createdSchedule;
  let customer;
  let dealerName;
  let dealerPhone;
  let offlineUnlockSecret;

  try {
    await client.query('BEGIN');

    const lockedRow = await client.query(
      `SELECT e.*, d.id AS dev_id
       FROM enrollments e
       JOIN devices d ON d.id = e.device_id
       WHERE e.id = $1
         AND e.status = 'pending'
         AND e.expires_at > NOW()
       LIMIT 1
       FOR UPDATE OF e`,
      [enrollment.id]
    );

    if (!lockedRow.rows.length) {
      const err = new Error('Code is incorrect or has expired. Ask your dealer to try again.');
      err.statusCode = 422;
      throw err;
    }

    [committedEnrollment] = lockedRow.rows;
    committedDealerIdentity = await resolveDealerIdentity(committedEnrollment.dealer_id, client);
    const keyTier = committedEnrollment.tier || 'standard';

    const identifierMatch = await client.query(
      `SELECT id, status
       FROM devices
       WHERE id <> $1
         AND (
           ($2::text IS NOT NULL AND imei = $2)
           OR ($3::text IS NOT NULL AND android_id = $3)
           OR ($4::text IS NOT NULL AND device_bound_id = $4)
         )
       ORDER BY
         CASE
           WHEN status = 'decoupled' THEN 0
           WHEN status = 'pending' THEN 1
           WHEN status = 'pending_decouple' THEN 2
           ELSE 3
         END,
         created_at DESC
       LIMIT 1
       FOR UPDATE`,
      [committedEnrollment.dev_id, imei || null, androidId || null, deviceBoundId || null]
    );

    if (identifierMatch.rows.length) {
      const matched = identifierMatch.rows[0];
      if (!['decoupled', 'pending', 'pending_decouple'].includes(matched.status)) {
        const err = new Error('This device is already enrolled.');
        err.statusCode = 409;
        throw err;
      }
      await client.query(`UPDATE enrollments SET device_id = $2 WHERE id = $1`, [
        committedEnrollment.id,
        matched.id
      ]);
      await client.query(
        `DELETE FROM devices
         WHERE id = $1 AND imei IS NULL AND owner_id IS NULL AND status = 'pending'`,
        [committedEnrollment.dev_id]
      );
      committedEnrollment.dev_id = matched.id;
      committedEnrollment.device_id = matched.id;
    }

    const keyRow = await client.query(
      `SELECT id, reseller_id
       FROM activation_keys
       WHERE dealer_id = ANY($1::uuid[])
         AND tier = $2
         AND status = 'assigned'
         AND device_id IS NULL
       ORDER BY created_at ASC
       LIMIT 1
       FOR UPDATE`,
      [committedDealerIdentity.keyDealerIds, keyTier]
    );

    if (!keyRow.rows.length) {
      const err = new Error(`No ready ${keyTier} activation code available for this dealer.`);
      err.statusCode = 409;
      throw err;
    }

    [consumedKey] = keyRow.rows;
    offlineUnlockSecret = createOfflineUnlockSecret();

    const customerResult = await client.query(
      `INSERT INTO users (email, name, phone, nid, role, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, 'customer', 'active', NOW(), NOW())
       ON CONFLICT (email) DO UPDATE SET
         name = EXCLUDED.name,
         phone = EXCLUDED.phone,
         nid = EXCLUDED.nid,
         updated_at = NOW()
       RETURNING id`,
      [
        createCustomerEmail({
          nidHash: committedEnrollment.nid_hash,
          phoneNumber: committedEnrollment.phone_number
        }),
        committedEnrollment.customer_name,
        committedEnrollment.phone_number,
        truncateNullable(committedEnrollment.nid_hash, 50)
      ]
    );
    [customer] = customerResult.rows;

    const dealerContactResult = await client.query(
      `SELECT name, phone FROM dealers WHERE id = $1 LIMIT 1`,
      [committedDealerIdentity.dealerRecordId]
    );
    dealerName = dealerContactResult.rows[0]?.name || null;
    dealerPhone = dealerContactResult.rows[0]?.phone || null;

    await client.query(
      `UPDATE activation_keys
       SET status = 'activated',
           device_id = $1,
           activated_at = NOW(),
           updated_at = NOW()
       WHERE id = $2`,
      [committedEnrollment.dev_id, consumedKey.id]
    );

    const reportedImei = normalizeImei(imei);
    await client.query(
      `UPDATE enrollments
       SET brand = COALESCE($2, brand),
           model = COALESCE($3, model),
           imei1 = COALESCE($4, imei1)
       WHERE id = $1`,
      [
        committedEnrollment.id,
        truncateNullable(brand, 64),
        truncateNullable(model, 64),
        reportedImei || null
      ]
    );

    await client.query(
      `UPDATE devices
       SET status            = 'enrolled',
           imei              = COALESCE($11, imei),
           android_id        = COALESCE($12, android_id),
           device_bound_id   = COALESCE($13, device_bound_id),
           brand             = $2,
           model             = $3,
           dealer_id         = $4,
           reseller_id       = COALESCE($5, reseller_id),
           activation_key_id = $6,
           owner_id          = $7,
           device_name       = COALESCE(device_name, $8),
           dealer_phone      = COALESCE(dealer_phone, $9),
           totp_secret       = COALESCE(totp_secret, $10),
           enrolled_at       = COALESCE(enrolled_at, NOW()),
           updated_at        = NOW()
       WHERE id = $1`,
      [
        committedEnrollment.dev_id,
        truncateNullable(brand, 64) || committedEnrollment.brand,
        truncateNullable(model, 64) || committedEnrollment.model,
        committedDealerIdentity.dealerRecordId,
        consumedKey.reseller_id || committedDealerIdentity.resellerId,
        consumedKey.id,
        customer.id,
        [
          truncateNullable(brand, 64) || committedEnrollment.brand,
          truncateNullable(model, 64) || committedEnrollment.model
        ]
          .filter(Boolean)
          .join(' ') || null,
        dealerPhone,
        offlineUnlockSecret,
        reportedImei || null,
        androidId || null,
        deviceBoundId || null
      ]
    );

    await client.query(
      `UPDATE enrollments SET status = 'confirmed', confirmed_at = NOW() WHERE id = $1`,
      [committedEnrollment.id]
    );

    if (
      committedEnrollment.total_amount &&
      committedEnrollment.emi_amount &&
      committedEnrollment.duration &&
      committedEnrollment.start_date
    ) {
      createdSchedule = await upsertActiveSchedule(client, committedEnrollment.dev_id, {
        totalAmount: committedEnrollment.total_amount,
        downPayment: committedEnrollment.down_payment || 0,
        emiAmount: committedEnrollment.emi_amount,
        duration: committedEnrollment.duration,
        startDate: committedEnrollment.start_date,
        graceDays: committedEnrollment.grace_days ?? 7
      });
    }

    // Create ownership assignment record for this enrollment period
    const assignmentId = await assignmentService.createAssignment(
      committedEnrollment.dev_id,
      {
        customerId: customer.id,
        dealerId: committedDealerIdentity.dealerRecordId,
        emiScheduleId: createdSchedule?.id ?? null
      },
      client
    );

    // Create device behavior profile (learning mode for first 30 days)
    await client.query(
      `INSERT INTO device_profiles (device_id, current_mode, learning_mode_ends_at)
       VALUES ($1, 'learning', NOW() + INTERVAL '30 days')
       ON CONFLICT (device_id) DO UPDATE
         SET current_mode = 'learning',
             learning_mode_ends_at = NOW() + INTERVAL '30 days',
             updated_at = NOW()`,
      [committedEnrollment.dev_id]
    );

    try {
      await client.query(
        `INSERT INTO device_history
           (device_id, assignment_id, event_type, actor_type, permanent, details)
         VALUES ($1, $2, 'ENROLLED', 'system', true, $3)`,
        [
          committedEnrollment.dev_id,
          assignmentId,
          JSON.stringify({ enrollment_id: committedEnrollment.id })
        ]
      );
    } catch (_) {}

    await client.query('COMMIT');
    logger.info('Activation key consumed', { keyId: consumedKey.id, tier: keyTier });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }

  logger.info('Device bound via user app', {
    enrollmentId: committedEnrollment.id,
    imei: imei ? imei.slice(-4) : 'unknown'
  });

  try {
    const devRow = await db.query(`SELECT id, device_name, imei FROM devices WHERE id = $1`, [
      committedEnrollment.dev_id
    ]);
    if (devRow.rows.length) {
      emitEnrollmentComplete(devRow.rows[0], committedDealerIdentity.dealerRecordId);
    }
  } catch (error) {
    logger.warn('Enrollment SSE emit failed', { error: error.message });
  }

  const deviceToken = createDeviceToken({
    deviceId: committedEnrollment.dev_id,
    dealerId: committedDealerIdentity.dealerRecordId,
    resellerId: consumedKey.reseller_id || committedDealerIdentity.resellerId
  });
  return {
    success: true,
    device_id: committedEnrollment.dev_id,
    device_token: deviceToken,
    offline_unlock_secret: offlineUnlockSecret,
    dealer_name: dealerName,
    dealer_phone: dealerPhone,
    emi_schedule: formatSchedule(createdSchedule)
  };
}

module.exports = {
  startEnrollment,
  confirmFromDevice,
  formatSchedule,
  saveEnrollmentDeviceFallback,
  saveEnrollmentEmiTerms
};
