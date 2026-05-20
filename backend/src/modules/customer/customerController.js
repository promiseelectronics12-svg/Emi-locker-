const { OAuth2Client } = require('google-auth-library');
const db = require('../../config/database');
const logger = require('../../utils/logger');
const {
  generateAccessToken,
  generateRefreshToken,
  storeRefreshToken
} = require('../auth/jwt');

const googleClient = new OAuth2Client();

// Fix 3: match auth/index.js pattern — split comma-separated GOOGLE_AUTH_CLIENT_IDS
function getGoogleAudiences() {
  return [
    process.env.GOOGLE_AUTH_CLIENT_IDS,
    process.env.GOOGLE_WEB_CLIENT_ID,
    process.env.GOOGLE_ANDROID_CLIENT_ID,
    process.env.GOOGLE_CLIENT_ID
  ]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim())
    .filter(Boolean);
}

async function verifyGoogleIdToken(idToken) {
  const audiences = getGoogleAudiences();
  if (audiences.length === 0) {
    const err = new Error('Google auth client IDs not configured');
    err.code = 'GOOGLE_AUTH_NOT_CONFIGURED';
    throw err;
  }
  const ticket = await googleClient.verifyIdToken({ idToken, audience: audiences });
  const payload = ticket.getPayload();
  if (!payload?.sub || !payload?.email) {
    const err = new Error('Google token missing identity claims');
    err.code = 'INVALID_GOOGLE_TOKEN';
    throw err;
  }
  return {
    sub: payload.sub,
    email: payload.email.toLowerCase().trim(),
    emailVerified: payload.email_verified === true,
    name: payload.name || ''
  };
}

// POST /api/v1/customer/auth/google
// Body: { idToken, imei? }
// First-time: provide imei to bind Google account to enrolled device.
// Subsequent logins: idToken only (lookup by google_sub).
async function googleAuth(req, res) {
  const { idToken, imei } = req.body;

  if (!idToken) {
    return res.status(400).json({ status: 'error', code: 'MISSING_ID_TOKEN', message: 'idToken is required' });
  }

  let googleUser;
  try {
    googleUser = await verifyGoogleIdToken(idToken);
  } catch (err) {
    if (err.code === 'GOOGLE_AUTH_NOT_CONFIGURED') {
      return res.status(503).json({ status: 'error', code: err.code, message: err.message });
    }
    logger.warn('[customer/auth] Google token verification failed:', err.message);
    return res.status(401).json({ status: 'error', code: 'INVALID_GOOGLE_TOKEN', message: 'Google token invalid or expired' });
  }

  try {
    let user = null;

    // Returning user: lookup by google_sub
    const googleAccountResult = await db.query(
      `SELECT u.id, u.email, u.role, u.status, u.name
       FROM user_google_accounts uga
       JOIN users u ON uga.user_id = u.id
       WHERE uga.google_sub = $1 AND u.role = 'customer' AND u.status = 'active'`,
      [googleUser.sub]
    );

    if (googleAccountResult.rows.length > 0) {
      [user] = googleAccountResult.rows;
      await db.query(
        `UPDATE user_google_accounts
         SET google_email = $1, google_email_verified = $2, last_used_at = NOW(), updated_at = NOW()
         WHERE google_sub = $3`,
        [googleUser.email, googleUser.emailVerified, googleUser.sub]
      );
    } else if (imei) {
      // First-time sign-in: find device by IMEI, get enrolled customer
      const deviceResult = await db.query(
        `SELECT d.id as device_id, d.owner_id, d.imei,
                u.id, u.email, u.role, u.status, u.name
         FROM devices d
         JOIN users u ON d.owner_id = u.id
         WHERE d.imei = $1 AND u.role = 'customer' AND u.status = 'active'
         LIMIT 1`,
        [imei]
      );

      if (deviceResult.rows.length === 0) {
        return res.status(404).json({
          status: 'error',
          code: 'DEVICE_NOT_ENROLLED',
          message: 'Device not found or not enrolled under a customer account'
        });
      }

      const row = deviceResult.rows[0];
      user = { id: row.id, email: row.email, role: row.role, status: row.status, name: row.name };

      await db.query(
        `INSERT INTO user_google_accounts (user_id, google_sub, google_email, google_email_verified, bound_at, last_used_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, NOW(), NOW(), NOW(), NOW())
         ON CONFLICT (google_sub) DO UPDATE
           SET google_email = EXCLUDED.google_email,
               google_email_verified = EXCLUDED.google_email_verified,
               last_used_at = NOW(),
               updated_at = NOW()`,
        [user.id, googleUser.sub, googleUser.email, googleUser.emailVerified]
      );
    } else {
      return res.status(401).json({
        status: 'error',
        code: 'ACCOUNT_NOT_FOUND',
        message: 'No account found. Provide your device IMEI on first sign-in.'
      });
    }

    const { token: accessToken } = generateAccessToken(user);
    const { token: refreshToken } = generateRefreshToken(user);
    await storeRefreshToken(user.id, refreshToken);

    return res.json({
      status: 'ok',
      token: accessToken,
      refreshToken,
      userId: user.id,
      name: googleUser.name || user.name || '',
      email: googleUser.email
    });
  } catch (err) {
    logger.error('[customer/auth] googleAuth error:', err);
    return res.status(500).json({ status: 'error', code: 'INTERNAL_ERROR', message: 'Authentication failed' });
  }
}

// POST /api/v1/customer/fcm-token
// Auth: customer JWT
// Body: { token }
// Fix 1: writes emi_locker_fcm_token — does NOT touch devices.fcm_token (reserved for DeviceProtectionService)
async function registerFcmToken(req, res) {
  const { token } = req.body;

  if (!token || typeof token !== 'string') {
    return res.status(400).json({ status: 'error', code: 'MISSING_TOKEN', message: 'FCM token is required' });
  }

  try {
    const result = await db.query(
      `UPDATE devices
       SET emi_locker_fcm_token = $1, emi_locker_fcm_token_updated_at = NOW(), updated_at = NOW()
       WHERE owner_id = $2
       RETURNING id`,
      [token, req.user.id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ status: 'error', code: 'NO_DEVICE', message: 'No device registered under this account' });
    }

    return res.json({ status: 'ok', updated: result.rowCount });
  } catch (err) {
    logger.error('[customer/fcm] registerFcmToken error:', err);
    return res.status(500).json({ status: 'error', code: 'INTERNAL_ERROR', message: 'Failed to register FCM token' });
  }
}

// GET /api/v1/customer/devices/:imei
// Auth: customer JWT
async function getDevice(req, res) {
  const { imei } = req.params;

  try {
    const result = await db.query(
      `SELECT d.id, d.imei, d.brand, d.model, d.device_name, d.status,
              d.lock_level, d.locked_at, d.locked_by,
              es.id as schedule_id, es.total_amount, es.emi_amount,
              es.duration, es.status as schedule_status,
              es.start_date, es.end_date
       FROM devices d
       LEFT JOIN emi_schedules es ON es.device_id = d.id AND es.status != 'cancelled'
       WHERE d.imei = $1 AND d.owner_id = $2
       ORDER BY es.created_at DESC
       LIMIT 1`,
      [imei, req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ status: 'error', code: 'DEVICE_NOT_FOUND', message: 'Device not found' });
    }

    const row = result.rows[0];
    return res.json({
      status: 'ok',
      device: {
        id: row.id,
        imei: row.imei,
        brand: row.brand,
        model: row.model,
        name: row.device_name,
        status: row.status,
        lockLevel: row.lock_level || null,
        lockedAt: row.locked_at || null
      },
      schedule: row.schedule_id ? {
        id: row.schedule_id,
        totalAmount: row.total_amount,
        emiAmount: row.emi_amount,
        duration: row.duration,
        status: row.schedule_status,
        startDate: row.start_date,
        endDate: row.end_date
      } : null
    });
  } catch (err) {
    logger.error('[customer/device] getDevice error:', err);
    return res.status(500).json({ status: 'error', code: 'INTERNAL_ERROR', message: 'Failed to fetch device' });
  }
}

// GET /api/v1/customer/schedule
// Auth: customer JWT
// Returns schedule + installments for primary device
async function getSchedule(req, res) {
  try {
    const deviceResult = await db.query(
      `SELECT d.id FROM devices d
       WHERE d.owner_id = $1 AND d.status != 'decommissioned'
       ORDER BY d.created_at ASC
       LIMIT 1`,
      [req.user.id]
    );

    if (deviceResult.rows.length === 0) {
      return res.status(404).json({ status: 'error', code: 'NO_DEVICE', message: 'No device registered under this account' });
    }

    const deviceId = deviceResult.rows[0].id;

    const schedResult = await db.query(
      `SELECT es.*,
              d.imei, d.brand, d.model, d.device_name, d.lock_level
       FROM emi_schedules es
       JOIN devices d ON es.device_id = d.id
       WHERE es.device_id = $1 AND es.status != 'cancelled'
       ORDER BY es.created_at DESC
       LIMIT 1`,
      [deviceId]
    );

    if (schedResult.rows.length === 0) {
      return res.status(404).json({ status: 'error', code: 'NO_SCHEDULE', message: 'No EMI schedule found' });
    }

    const sched = schedResult.rows[0];

    // Fetch installments with completed-payment join
    const installmentsResult = await db.query(
      `SELECT ei.*,
              ep.id as payment_id, ep.amount as paid_amount,
              ep.payment_date, ep.payment_method, ep.transaction_ref,
              ep.payment_status, ep.recorded_at
       FROM generate_installments($1, $2, $3, $4) ei
       LEFT JOIN LATERAL (
         SELECT id, amount, payment_date, payment_method, transaction_ref, payment_status, recorded_at
         FROM emi_payments
         WHERE emi_schedule_id = $5 AND installment_number = ei.installment_number
           AND payment_status = 'completed'
         ORDER BY recorded_at DESC
         LIMIT 1
       ) ep ON true
       ORDER BY ei.installment_number`,
      [deviceId, sched.total_amount, sched.emi_amount, sched.duration, sched.id]
    );

    // Fix 4: overdue = past due_date AND no completed payment row (ep.id IS NULL)
    const overdueResult = await db.query(
      `SELECT
         COUNT(*) FILTER (WHERE ei.due_date < NOW() AND ep.id IS NULL) AS overdue_count,
         MIN(ei.due_date) FILTER (WHERE ei.due_date < NOW() AND ep.id IS NULL) AS oldest_overdue
       FROM generate_installments($1, $2, $3, $4) ei
       LEFT JOIN LATERAL (
         SELECT id
         FROM emi_payments
         WHERE emi_schedule_id = $5 AND installment_number = ei.installment_number
           AND payment_status = 'completed'
         LIMIT 1
       ) ep ON true`,
      [deviceId, sched.total_amount, sched.emi_amount, sched.duration, sched.id]
    );

    const overdue = overdueResult.rows[0];

    return res.json({
      status: 'ok',
      schedule: {
        id: sched.id,
        totalAmount: sched.total_amount,
        emiAmount: sched.emi_amount,
        duration: sched.duration,
        scheduleStatus: sched.status,
        startDate: sched.start_date,
        endDate: sched.end_date,
        device: {
          imei: sched.imei,
          brand: sched.brand,
          model: sched.model,
          name: sched.device_name,
          lockLevel: sched.lock_level || null
        },
        installments: installmentsResult.rows,
        overdueCount: parseInt(overdue.overdue_count, 10),
        oldestOverdueDate: overdue.oldest_overdue || null
      }
    });
  } catch (err) {
    logger.error('[customer/schedule] getSchedule error:', err);
    return res.status(500).json({ status: 'error', code: 'INTERNAL_ERROR', message: 'Failed to fetch schedule' });
  }
}

module.exports = { googleAuth, registerFcmToken, getDevice, getSchedule };
