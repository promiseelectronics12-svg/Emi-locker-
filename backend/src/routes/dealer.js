const express = require('express');
const asyncHandler = require('express-async-handler');
const { body, param } = require('express-validator');
const crypto = require('crypto');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const { validateRequest } = require('../middleware/validateRequest');
const { buildErrorResponse } = require('../middleware/errorHandler');
const smsService = require('../modules/notifications/sms.service');
const { getDealerInventory } = require('../modules/keys/keyController');
const lockCommandService = require('../modules/lock/lockCommandService');
const lockDeliveryService = require('../modules/lock/lockDeliveryService');
const { LOCK_LEVELS } = require('../modules/lock/lockVerificationService');

const router = express.Router();

router.use(authenticateToken);
router.use(requireRole('dealer'));

// ─── Helpers ───────────────────────────────────────────────────────────────

async function getDealerProfile(userId) {
  const result = await db.query('SELECT * FROM dealers WHERE user_id = $1 OR id = $1 LIMIT 1', [
    userId
  ]);
  return result.rows[0] || null;
}

function getDealerIds(userId, dealer) {
  const ids = [userId];
  if (dealer?.id) ids.push(dealer.id);
  return ids;
}

function warnOptionalFailure(scope, error) {
  console.warn(`[DealerRoute] ${scope} failed:`, error.message);
}

function isDeviceStatusConstraintError(error) {
  return (
    error?.code === '23514' &&
    (error.constraint === 'devices_status_check' ||
      error.message?.includes('devices_status_check'))
  );
}

function getCreditRecommendation(tier) {
  if (tier === 'GOLD') return 'Fast track — trusted customer';
  if (tier === 'SILVER') return 'Standard process';
  if (tier === 'BRONZE') return 'Verify carefully';
  return 'High risk — additional deposit recommended';
}

/** Generates a 6-digit HOTP from a base32 secret and a counter. */
function generateHOTP(base32Secret, counter) {
  const secret = Buffer.from(base32Secret, 'base64');
  const buf = Buffer.alloc(8);
  let tmp = counter;
  for (let i = 7; i >= 0; i--) {
    buf[i] = tmp & 0xff;
    tmp >>>= 8;
  }
  const hmac = crypto.createHmac('sha1', secret).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const code =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return String(code % 1000000).padStart(6, '0');
}

/**
 * Grace-period HOTP encoding.
 * Counter = timeWindow * 10 + graceIndex (1–4).
 * Each grace duration produces a unique 6-digit code for the same time window.
 * The device app tries all 4 indices to identify which duration was granted.
 */
const GRACE_INDEX = { 2: 1, 4: 2, 8: 3, 24: 4 };

const DEFAULT_USER_APP_APK_URL =
  'https://raw.githubusercontent.com/promiseelectronics12-svg/Emi-locker-/apk-releases/user-app/1.0.0/emi-locker-user-1.0.0-release.apk';
const DEFAULT_USER_APP_APK_CHECKSUM = 'G5hnEcbkVwO1XJ_-QUmlN1CCRepTwXIa-5DK2g9SKGo';
const USER_APP_PACKAGE = 'com.android.simtoolkit';
const USER_APP_ADMIN_RECEIVER = `${USER_APP_PACKAGE}/com.android.simtoolkit.device.DeviceAdminReceiver`;

function generateGraceHOTP(base32Secret, timeWindow, graceHours) {
  const idx = GRACE_INDEX[graceHours];
  if (!idx) throw new Error(`Invalid grace_hours: ${graceHours}`);
  return generateHOTP(base32Secret, timeWindow * 10 + idx);
}

async function checkOtpRateLimit(key, limit, ttlSeconds) {
  try {
    const redis = require('../config/redis');
    const attempts = await redis.incr(key);
    if (attempts === 1) await redis.expire(key, ttlSeconds);
    return attempts <= limit;
  } catch (error) {
    console.warn('OTP rate limiter unavailable; allowing request:', error.message);
    return true;
  }
}

const DEFAULT_SETTINGS = {
  offline_grace_hours: 72,
  warning_threshold_hours: 12,
  checkin_interval_minutes: 360,
  default_lock_level: 'FULL',
  lock_screen_message: null,
  lock_screen_dealer_name: null,
  lock_screen_dealer_phone: null
};

// ─── Existing routes ───────────────────────────────────────────────────────

router.get(
  '/stats',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const stats = await db.query(
      `SELECT
       COUNT(*)::int as total_devices,
       COUNT(*) FILTER (WHERE status = 'locked')::int as locked_devices,
       COUNT(*) FILTER (WHERE status = 'enrolled')::int as enrolled_devices,
       COUNT(*) FILTER (WHERE status = 'decoupled')::int as decoupled_devices
     FROM devices
     WHERE dealer_id = ANY($1::uuid[])`,
      [dealerIds]
    );

    const keys = await db.query(
      `SELECT
       COUNT(*) FILTER (WHERE status = 'assigned')::int as assigned_keys,
       COUNT(*) FILTER (WHERE status = 'activated')::int as activated_keys
     FROM activation_keys
     WHERE dealer_id = ANY($1::uuid[])`,
      [dealerIds]
    );

    return res.json({ ...stats.rows[0], ...keys.rows[0] });
  })
);

router.get('/keys/inventory', asyncHandler(getDealerInventory));

router.get(
  '/analytics',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const result = await db.query(
      `SELECT
       date_trunc('day', created_at)::date as day,
       COUNT(*)::int as devices_enrolled
     FROM devices
     WHERE dealer_id = ANY($1::uuid[])
       AND created_at > NOW() - INTERVAL '30 days'
     GROUP BY day
     ORDER BY day`,
      [dealerIds]
    );

    return res.json({ series: result.rows });
  })
);

router.get(
  '/devices',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const result = await db.query(
      `SELECT d.*,
            COALESCE(u.name, e.customer_name) AS customer_name,
            COALESCE(u.phone, e.phone_number) AS customer_phone,
            es.id AS emi_schedule_id,
            es.status AS emi_status,
            es.duration AS emi_duration,
            es.start_date AS emi_start_date,
            es.grace_days AS emi_grace_days,
            lr.reason_code AS latest_lock_reason,
            lr.note AS latest_lock_note,
            lr.status AS latest_lock_request_status,
            lr.created_at AS latest_lock_request_at,
            CASE
              WHEN d.fcm_token_status = 'invalid' OR d.app_uninstall_suspected_at IS NOT NULL THEN 'app_removed_suspected'
              WHEN d.device_health_status = 'degraded' THEN 'protection_degraded'
              WHEN d.last_seen_at IS NULL THEN 'never_seen'
              WHEN d.last_seen_at < NOW() - INTERVAL '150 minutes' THEN 'offline'
              WHEN d.last_seen_at < NOW() - INTERVAL '75 minutes' THEN 'delayed'
              ELSE 'online'
            END AS device_connection_status,
            d.last_seen_at,
            d.device_health_status,
            d.last_heartbeat_source,
            d.fcm_token_status,
            d.app_uninstall_suspected_at,
            CASE
              WHEN d.last_location_at IS NULL THEN TRUE
              WHEN d.last_location_at < NOW() - INTERVAL '15 minutes' THEN TRUE
              ELSE FALSE
            END AS location_is_stale,
            CASE
              WHEN d.last_location_at IS NULL THEN NULL
              ELSE FLOOR(EXTRACT(EPOCH FROM (NOW() - d.last_location_at)) / 60)::int
            END AS last_location_age_minutes
     FROM devices d
     LEFT JOIN users u ON u.id = d.owner_id
     LEFT JOIN LATERAL (
       SELECT customer_name, phone_number
       FROM enrollments
       WHERE device_id = d.id
       ORDER BY created_at DESC
       LIMIT 1
     ) e ON TRUE
     LEFT JOIN emi_schedules es ON es.device_id = d.id AND es.status = 'active'
     LEFT JOIN LATERAL (
       SELECT reason_code, note, status, created_at
       FROM lock_requests
       WHERE device_id = d.id
       ORDER BY created_at DESC
       LIMIT 1
     ) lr ON TRUE
     WHERE d.dealer_id = ANY($1::uuid[])
     ORDER BY d.created_at DESC`,
      [dealerIds]
    );

    return res.json({ devices: result.rows, total: result.rows.length });
  })
);

// ─── Dealer-level defaults ─────────────────────────────────────────────────

router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    if (!dealer)
      return res
        .status(404)
        .json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer profile not found'));

    const result = await db.query('SELECT * FROM dealer_defaults WHERE dealer_id = $1', [
      dealer.id
    ]);
    return res.json(result.rows[0] || { dealer_id: dealer.id, ...DEFAULT_SETTINGS });
  })
);

router.put(
  '/settings',
  body('offline_grace_hours').optional().isInt({ min: 24, max: 168 }),
  body('warning_threshold_hours').optional().isInt({ min: 1, max: 48 }),
  body('checkin_interval_minutes').optional().isInt({ min: 60, max: 1440 }),
  body('default_lock_level').optional().isIn(['SOFT', 'FULL']),
  body('lock_screen_dealer_name').optional({ nullable: true }).isString().isLength({ max: 80 }),
  body('lock_screen_dealer_phone').optional({ nullable: true }).isString().isLength({ max: 20 }),
  body('lock_screen_message').optional({ nullable: true }).isString().isLength({ max: 200 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    if (!dealer)
      return res
        .status(404)
        .json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer profile not found'));

    const {
      offline_grace_hours = DEFAULT_SETTINGS.offline_grace_hours,
      warning_threshold_hours = DEFAULT_SETTINGS.warning_threshold_hours,
      checkin_interval_minutes = DEFAULT_SETTINGS.checkin_interval_minutes,
      default_lock_level = DEFAULT_SETTINGS.default_lock_level,
      lock_screen_dealer_name = null,
      lock_screen_dealer_phone = null,
      lock_screen_message = null
    } = req.body;

    await db.query(
      `INSERT INTO dealer_defaults
         (dealer_id, offline_grace_hours, warning_threshold_hours,
          checkin_interval_minutes, default_lock_level,
          lock_screen_dealer_name, lock_screen_dealer_phone, lock_screen_message,
          updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW())
       ON CONFLICT (dealer_id) DO UPDATE SET
         offline_grace_hours      = EXCLUDED.offline_grace_hours,
         warning_threshold_hours  = EXCLUDED.warning_threshold_hours,
         checkin_interval_minutes = EXCLUDED.checkin_interval_minutes,
         default_lock_level       = EXCLUDED.default_lock_level,
         lock_screen_dealer_name  = EXCLUDED.lock_screen_dealer_name,
         lock_screen_dealer_phone = EXCLUDED.lock_screen_dealer_phone,
         lock_screen_message      = EXCLUDED.lock_screen_message,
         updated_at               = NOW()`,
      [
        dealer.id,
        offline_grace_hours,
        warning_threshold_hours,
        checkin_interval_minutes,
        default_lock_level,
        lock_screen_dealer_name,
        lock_screen_dealer_phone,
        lock_screen_message
      ]
    );

    return res.json({ success: true });
  })
);

// ─── Per-device settings ───────────────────────────────────────────────────

router.get(
  '/devices/:deviceId/settings',
  param('deviceId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    // Confirm device belongs to this dealer
    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    const result = await db.query('SELECT * FROM dealer_device_settings WHERE device_id = $1', [
      req.params.deviceId
    ]);
    return res.json(result.rows[0] || { device_id: req.params.deviceId, ...DEFAULT_SETTINGS });
  })
);

router.put(
  '/devices/:deviceId/settings',
  param('deviceId').isUUID(),
  body('offline_grace_hours').optional().isInt({ min: 24, max: 168 }),
  body('warning_threshold_hours').optional().isInt({ min: 1, max: 48 }),
  body('checkin_interval_minutes').optional().isInt({ min: 60, max: 1440 }),
  body('default_lock_level').optional().isIn(['SOFT', 'FULL']),
  body('lock_screen_dealer_name').optional({ nullable: true }).isString().isLength({ max: 80 }),
  body('lock_screen_dealer_phone').optional({ nullable: true }).isString().isLength({ max: 20 }),
  body('lock_screen_message').optional({ nullable: true }).isString().isLength({ max: 200 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    const {
      offline_grace_hours = DEFAULT_SETTINGS.offline_grace_hours,
      warning_threshold_hours = DEFAULT_SETTINGS.warning_threshold_hours,
      checkin_interval_minutes = DEFAULT_SETTINGS.checkin_interval_minutes,
      default_lock_level = DEFAULT_SETTINGS.default_lock_level,
      lock_screen_dealer_name = null,
      lock_screen_dealer_phone = null,
      lock_screen_message = null
    } = req.body;

    await db.query(
      `INSERT INTO dealer_device_settings
         (device_id, dealer_id, offline_grace_hours, warning_threshold_hours,
          checkin_interval_minutes, default_lock_level,
          lock_screen_dealer_name, lock_screen_dealer_phone, lock_screen_message,
          updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,NOW())
       ON CONFLICT (device_id) DO UPDATE SET
         offline_grace_hours      = EXCLUDED.offline_grace_hours,
         warning_threshold_hours  = EXCLUDED.warning_threshold_hours,
         checkin_interval_minutes = EXCLUDED.checkin_interval_minutes,
         default_lock_level       = EXCLUDED.default_lock_level,
         lock_screen_dealer_name  = EXCLUDED.lock_screen_dealer_name,
         lock_screen_dealer_phone = EXCLUDED.lock_screen_dealer_phone,
         lock_screen_message      = EXCLUDED.lock_screen_message,
         updated_at               = NOW()`,
      [
        req.params.deviceId,
        dealer.id,
        offline_grace_hours,
        warning_threshold_hours,
        checkin_interval_minutes,
        default_lock_level,
        lock_screen_dealer_name,
        lock_screen_dealer_phone,
        lock_screen_message
      ]
    );

    return res.json({ success: true });
  })
);

// ─── SMS OTP grace-period offline unlock ──────────────────────────────────
//
// Flow:
//   1. Customer calls dealer from another phone (their number is shown on locked screen)
//   2. Dealer agrees to a grace period, selects duration in their app, taps "Send code"
//   3. Backend generates a grace-encoded HOTP and sends it to the customer's number via SMS
//   4. Customer enters the 6-digit code on the locked screen — no internet required
//   5. Device validates locally using stored TOTP secret and auto-locks after grace expires
//
// Code encoding: counter = timeWindow * 10 + graceIndex (1=2h, 2=4h, 3=8h, 4=24h)
// Valid for one 30-minute window from issue time.

router.post(
  '/devices/:deviceId/paut/sms-otp',
  param('deviceId').isUUID(),
  body('grace_hours')
    .optional()
    .isInt()
    .custom((v) => [2, 4, 8, 24].includes(Number(v)))
    .withMessage('grace_hours must be 2, 4, 8, or 24'),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const result = await db.query(
      `SELECT d.id, d.totp_secret, d.model, d.brand,
              u.phone AS customer_phone, u.name AS customer_name
       FROM devices d
       LEFT JOIN users u ON u.id = d.owner_id
       WHERE d.id = $1 AND d.dealer_id = ANY($2::uuid[])`,
      [req.params.deviceId, dealerIds]
    );

    if (!result.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    const device = result.rows[0];

    if (!device.totp_secret)
      return res
        .status(400)
        .json(
          buildErrorResponse(
            400,
            'NO_TOTP',
            'Device does not have an offline unlock secret. Re-enroll the device to enable SMS unlock.'
          )
        );

    if (!device.customer_phone)
      return res
        .status(400)
        .json(
          buildErrorResponse(400, 'NO_PHONE', 'No customer phone number on record for this device.')
        );

    const graceHours = Number(req.body.grace_hours) || 4;
    const timeWindow = Math.floor(Date.now() / (30 * 60 * 1000));

    // Rate limit: max 3 OTP requests per device per 30-minute window
    const rateLimitKey = `sms_otp:${req.params.deviceId}:${timeWindow}`;
    const allowed = await checkOtpRateLimit(rateLimitKey, 3, 30 * 60);
    if (!allowed)
      return res
        .status(429)
        .json(
          buildErrorResponse(429, 'RATE_LIMITED', 'Too many OTP requests. Try again in 30 minutes.')
        );

    // Generate grace-encoded HOTP (each duration produces a unique code)
    const otp = generateGraceHOTP(device.totp_secret, timeWindow, graceHours);

    const dealerName = dealer?.name || dealer?.business_name || 'your dealer';
    const deviceLabel = [device.brand, device.model].filter(Boolean).join(' ') || 'your device';
    const maskedPhone = device.customer_phone.replace(/(\d{2})\d+(\d{3})/, '$1****$2');

    await smsService.sendSMS(
      device.customer_phone,
      `EMI Locker: Unlock code for ${deviceLabel} is ${otp}. Valid for 30 minutes — unlocks for ${graceHours} hours. Device will re-lock automatically after. Contact ${dealerName} for help.`
    );

    // Log the grace unlock event for audit
    try {
      const expiresAt = new Date(Date.now() + graceHours * 60 * 60 * 1000);
      await db.query(
        `INSERT INTO grace_unlock_events
           (device_id, dealer_id, grace_hours, otp_window, expires_at, sms_sent_to)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          req.params.deviceId,
          dealer.id,
          graceHours,
          timeWindow * 10 + GRACE_INDEX[graceHours],
          expiresAt,
          maskedPhone
        ]
      );
    } catch (_) {
      // Non-fatal — migration 101 may not have run yet
    }

    return res.json({
      sent: true,
      grace_hours: graceHours,
      expires_minutes: 30,
      masked_phone: maskedPhone
    });
  })
);

// ─── Active grace unlock for a device ─────────────────────────────────────

router.get(
  '/devices/:deviceId/grace-unlock',
  param('deviceId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    let active = null;
    try {
      const result = await db.query(
        `SELECT id, grace_hours, issued_at, expires_at, sms_sent_to
         FROM grace_unlock_events
         WHERE device_id = $1 AND revoked = FALSE AND expires_at > NOW()
         ORDER BY issued_at DESC
         LIMIT 1`,
        [req.params.deviceId]
      );
      active = result.rows[0] || null;
    } catch (error) {
      warnOptionalFailure('active grace unlock lookup', error);
    }

    return res.json({ active });
  })
);

// ─── Revoke an active grace unlock (re-lock the device early) ─────────────
// Note: this only marks the server record as revoked. The device itself will
// not receive the revoke signal until the next check-in (or via push notification
// if the device has internet access). The device app must honour the revoke flag.

router.delete(
  '/devices/:deviceId/grace-unlock',
  param('deviceId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    try {
      await db.query(
        `UPDATE grace_unlock_events
         SET revoked = TRUE, revoked_at = NOW()
         WHERE device_id = $1 AND revoked = FALSE AND expires_at > NOW()`,
        [req.params.deviceId]
      );
    } catch (error) {
      warnOptionalFailure('grace unlock revoke', error);
    }

    return res.json({ revoked: true });
  })
);

// ─── Device search ────────────────────────────────────────────────────────
// Dealer searches for a device by customer name, phone, IMEI, or model/brand.
// Used at the start of the unlock workflow: dealer finds the device, then calls
// lock-detail to understand the situation before deciding how to unlock.

router.get(
  '/devices/search',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);
    const q = (req.query.q || '').trim();

    if (!q || q.length < 2)
      return res
        .status(400)
        .json(
          buildErrorResponse(400, 'QUERY_TOO_SHORT', 'Search query must be at least 2 characters')
        );

    const result = await db.query(
      `SELECT d.id, d.imei, d.model, d.brand, d.status, d.grace_expires_at,
            u.name  AS customer_name,
            REGEXP_REPLACE(u.phone, '(\\d{2})\\d+(\\d{3})', '\\1****\\2') AS masked_phone
     FROM devices d
     LEFT JOIN users u ON u.id = d.owner_id
     WHERE d.dealer_id = ANY($1::uuid[])
       AND (
         u.name  ILIKE $2 OR
         u.phone ILIKE $2 OR
         d.imei  ILIKE $2 OR
         d.model ILIKE $2 OR
         d.brand ILIKE $2
       )
     ORDER BY d.created_at DESC
     LIMIT 20`,
      [dealerIds, `%${q}%`]
    );

    return res.json({ devices: result.rows, total: result.rows.length });
  })
);

// ─── Lock detail — full situation view before unlock ──────────────────────
// Returns everything the dealer needs in a single call to decide how to unlock.
// This replaces the need for multiple API round-trips when a customer calls.

router.get(
  '/devices/:deviceId/lock-detail',
  param('deviceId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const result = await db.query(
      `SELECT d.id, d.imei, d.model, d.brand, d.status, d.lock_level,
              d.grace_expires_at, d.dealer_phone, d.totp_secret,
              COALESCE(u.name, e.customer_name)  AS customer_name,
              COALESCE(u.phone, e.phone_number) AS customer_phone,
              lr.reason_code AS lock_reason,
              lr.created_at  AS locked_at,
              es.duration    AS emi_total,
              COALESCE(
                (SELECT COUNT(*) FROM emi_payments ep
                 WHERE ep.emi_schedule_id = es.id AND ep.status = 'completed'), 0
              ) AS emi_paid,
              es.status AS emi_status
       FROM devices d
       LEFT JOIN users u ON u.id = d.owner_id
       LEFT JOIN LATERAL (
         SELECT customer_name, phone_number
         FROM enrollments
         WHERE device_id = d.id
         ORDER BY created_at DESC
         LIMIT 1
       ) e ON TRUE
       LEFT JOIN LATERAL (
         SELECT reason_code, created_at FROM lock_requests
         WHERE device_id = d.id AND status = 'approved'
         ORDER BY created_at DESC LIMIT 1
       ) lr ON TRUE
       LEFT JOIN emi_schedules es ON es.device_id = d.id AND es.status = 'active'
       WHERE d.id = $1 AND d.dealer_id = ANY($2::uuid[])`,
      [req.params.deviceId, dealerIds]
    );

    if (!result.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    const row = result.rows[0];
    const emiPaid = Number(row.emi_paid) || 0;
    const emiTotal = Number(row.emi_total) || 0;
    const emiFullyPaid = emiTotal > 0 && emiPaid >= emiTotal;

    // Calculate days overdue from lock_requests if available
    let daysOverdue = 0;
    if (row.locked_at && row.lock_reason === 'EMI_OVERDUE') {
      daysOverdue = Math.floor((Date.now() - new Date(row.locked_at)) / (1000 * 60 * 60 * 24));
    }

    // Active grace unlock
    let activeGrace = null;
    try {
      const graceRes = await db.query(
        `SELECT grace_hours, expires_at, issued_at FROM grace_unlock_events
         WHERE device_id = $1 AND revoked_at IS NULL AND expires_at > NOW()
         ORDER BY issued_at DESC LIMIT 1`,
        [row.id]
      );
      activeGrace = graceRes.rows[0] || null;
    } catch (error) {
      warnOptionalFailure('lock detail active grace lookup', error);
    }

    return res.json({
      device: {
        id: row.id,
        imei: row.imei,
        model: row.model,
        brand: row.brand
      },
      customer: {
        name: row.customer_name || null,
        masked_phone: row.customer_phone
          ? row.customer_phone.replace(/(\d{2})\d+(\d{3})/, '$1****$2')
          : null
      },
      lock: {
        is_locked: !!(row.lock_level && row.lock_level !== 'NONE'),
        lock_level: row.lock_level || null,
        reason: row.lock_reason || null,
        locked_at: row.locked_at || null,
        days_overdue: daysOverdue
      },
      emi: {
        installments_paid: emiPaid,
        installments_total: emiTotal,
        fully_paid: emiFullyPaid,
        days_overdue: daysOverdue
      },
      active_grace: activeGrace,
      unlock_options: {
        online_available: true,
        offline_available: !!row.totp_secret
      }
    });
  })
);

// ─── Unified unlock (online + offline, always with grace period) ───────────
//
// Every unlock has a grace period — device auto-relocks when it expires.
// This creates natural payment motivation without dealer needing to manually re-lock.
//
// Online:  Server sends FCM unlock command + sets grace_expires_at on device record.
//          Lock scheduler re-locks when grace expires.
// Offline: Generates grace-encoded HOTP + returns pre-filled SMS text.
//          Dealer sends SMS from THEIR OWN PHONE (no Twilio). Customer receives SMS
//          from the dealer's real number — trustworthy and free.
//          Device validates TOTP locally — no internet required.
//
// TOTP window: current AND previous 30-minute window are both accepted.
// This gives up to 60 minutes of effective code validity, handling SMS delivery delays.

router.post(
  '/devices/:deviceId/unlock',
  param('deviceId').isUUID(),
  body('method').isIn(['online', 'offline']),
  body('grace_hours')
    .isInt()
    .custom((v) => [2, 4, 8, 24].includes(Number(v)))
    .withMessage('grace_hours must be 2, 4, 8, or 24'),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const result = await db.query(
      `SELECT d.id, d.imei, d.totp_secret, d.model, d.brand, d.status, d.fcm_token,
              d.device_name, d.amapi_device_name,
              COALESCE(u.phone, e.phone_number) AS customer_phone,
              COALESCE(u.name, e.customer_name) AS customer_name,
              d.dealer_phone
       FROM devices d
       LEFT JOIN users u ON u.id = d.owner_id
       LEFT JOIN LATERAL (
         SELECT customer_name, phone_number
         FROM enrollments
         WHERE device_id = d.id
         ORDER BY created_at DESC
         LIMIT 1
       ) e ON TRUE
       WHERE d.id = $1 AND d.dealer_id = ANY($2::uuid[])`,
      [req.params.deviceId, dealerIds]
    );

    if (!result.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    const device = result.rows[0];
    const graceHours = Number(req.body.grace_hours);
    const { method } = req.body;
    const expiresAt = new Date(Date.now() + graceHours * 60 * 60 * 1000);
    const maskedPhone = device.customer_phone
      ? device.customer_phone.replace(/(\d{2})\d+(\d{3})/, '$1****$2')
      : null;

    const timeWindow = Math.floor(Date.now() / (30 * 60 * 1000));

    async function recordGraceUnlockEvent(otpWindow) {
      try {
        await db.query(
          `INSERT INTO grace_unlock_events
             (device_id, dealer_id, grace_hours, otp_window, expires_at, sms_sent_to)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [device.id, dealer.id, graceHours, otpWindow, expiresAt, maskedPhone || 'unknown']
        );
      } catch (error) {
        warnOptionalFailure('grace unlock event insert', error);
      }
    }

    async function markOnlineUnlockPending(otpWindow) {
      try {
        await db.query(
          `UPDATE devices
           SET grace_expires_at = $1,
               status = 'pending_unlock',
               updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, device.id]
        );
      } catch (error) {
        if (!isDeviceStatusConstraintError(error)) throw error;

        console.warn(
          '[DealerRoute] devices_status_check does not allow pending_unlock; keeping current device status until confirmation.',
          { deviceId: device.id }
        );
        await db.query(
          `UPDATE devices
           SET grace_expires_at = $1,
               updated_at = NOW()
           WHERE id = $2`,
          [expiresAt, device.id]
        );
      }
      await recordGraceUnlockEvent(otpWindow);
    }

    if (method === 'online') {
      await markOnlineUnlockPending(timeWindow * 10 + GRACE_INDEX[graceHours]);

      // Send the same signed command format that the release user app verifies.
      let delivery = null;
      try {
        const command = await lockCommandService.generateSignedCommand({
          deviceImei: device.imei,
          actionType: 'UNLOCK',
          lockLevel: LOCK_LEVELS.NONE,
          metadata: {
            reason: 'DEALER_GRACE_UNLOCK',
            graceHours,
            expiresAt: expiresAt.toISOString()
          }
        });
        delivery = await lockDeliveryService.deliverCommand(device.id, command, LOCK_LEVELS.NONE);
      } catch (error) {
        console.warn('Online unlock delivery failed:', error.message);
      }

      try {
        const sseService = require('../modules/sse/sseService');
        const payload = {
          deviceId: device.id,
          deviceName: device.device_name || device.amapi_device_name,
          status: 'pending_unlock',
          graceHours,
          expiresAt: expiresAt.toISOString(),
          requestedAt: new Date().toISOString()
        };
        sseService.pushToDealer(dealer.id, 'device_unlock_pending', payload);
        sseService.pushToManagement('device_unlock_pending', payload);
      } catch (error) {
        warnOptionalFailure('online unlock pending SSE emit', error);
      }

      return res.json({
        method: 'online',
        status: 'pending',
        device_confirmed: false,
        message: 'Unlock command sent. Waiting for device confirmation.',
        grace_hours: graceHours,
        expires_at: expiresAt.toISOString(),
        fcm_sent: delivery?.results?.fcm?.success === true,
        delivery: delivery?.results || null
      });
    }

    // Offline path — generate HOTP, return SMS text for dealer to send from their phone
    if (!device.totp_secret)
      return res
        .status(400)
        .json(
          buildErrorResponse(
            400,
            'NO_TOTP',
            'Device does not have an offline unlock secret. Re-enroll the device to enable offline unlock.'
          )
        );

    if (!device.customer_phone)
      return res
        .status(400)
        .json(
          buildErrorResponse(400, 'NO_PHONE', 'No customer phone number on record for this device.')
        );

    // Rate limit: max 3 OTP requests per device per 30-minute window
    const rateLimitKey = `unlock_otp:${device.id}:${timeWindow}`;
    const allowed = await checkOtpRateLimit(rateLimitKey, 3, 30 * 60);
    if (!allowed)
      return res
        .status(429)
        .json(
          buildErrorResponse(
            429,
            'RATE_LIMITED',
            'Too many unlock requests. Try again in 30 minutes.'
          )
        );

    // Generate grace-encoded HOTP — accept current AND previous window (up to 60 min validity)
    const otp = generateGraceHOTP(device.totp_secret, timeWindow, graceHours);

    // Structured SMS format — device app parses this automatically
    // Format: EMI-GRACE:<OTP>:<Xh>:<unix_timestamp>
    const smsText = `EMI-GRACE:${otp}:${graceHours}H:${timeWindow * 30 * 60}`;
    const dealerName = dealer?.name || dealer?.business_name || 'your dealer';
    const deviceLabel = [device.brand, device.model].filter(Boolean).join(' ') || 'your device';

    // Human-readable version for dealers who want to send a plain message
    const humanSmsText =
      `EMI Locker: ${deviceLabel} unlock code is ${otp}. ` +
      `Valid 60 min — unlocks for ${graceHours} hours then re-locks. ` +
      `Contact ${dealerName} for help.`;

    return res.json({
      method: 'offline',
      otp,
      grace_hours: graceHours,
      sms_text: smsText, // machine-parseable (for auto-SMS app)
      human_sms_text: humanSmsText, // readable (for manual send)
      customer_phone: device.customer_phone,
      masked_phone: maskedPhone,
      expires_at: expiresAt.toISOString(),
      valid_minutes: 60 // current + previous window
    });
  })
);

// Test-only decoupling control for live device-owner QA.
// Production decoupling still belongs to the admin/payment-approved flow.
router.post(
  '/devices/:deviceId/test-decouple',
  param('deviceId').isUUID(),
  body('confirm').equals('DECOUPLE').withMessage('confirm must be DECOUPLE'),
  validateRequest,
  asyncHandler(async (req, res) => {
    const isDemoAccount = ['dealer@emi-locker.com'].includes(
      String(req.user.email || '').toLowerCase()
    );
    const testEnabled = process.env.ENABLE_DEALER_TEST_DECOUPLE === 'true' || isDemoAccount;
    if (!testEnabled) {
      return res
        .status(403)
        .json(buildErrorResponse(403, 'TEST_DECOUPLE_DISABLED', 'Test decoupling is disabled'));
    }

    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);
    const result = await db.query(
      `SELECT id, imei, fcm_token, fcm_token_status, device_name, dealer_id, status
       FROM devices
       WHERE id = $1 AND dealer_id = ANY($2::uuid[])`,
      [req.params.deviceId, dealerIds]
    );

    if (!result.rows.length) {
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));
    }

    const device = result.rows[0];
    if (device.status === 'decoupled') {
      return res
        .status(409)
        .json(buildErrorResponse(409, 'ALREADY_DECOUPLED', 'Device already decoupled'));
    }
    if (!device.fcm_token) {
      return res
        .status(400)
        .json(buildErrorResponse(400, 'NO_FCM_TOKEN', 'Device has no active push token'));
    }

    let fcmResult;
    try {
      const fcmService = require('../modules/notifications/fcm.service');
      const signedCommand = await lockCommandService.generateSignedCommand({
        deviceImei: device.imei || '',
        actionType: 'DECOUPLE',
        lockLevel: 'NONE',
        metadata: { reason: 'DEALER_TEST_DECOUPLE', deviceId: device.id },
      });
      fcmResult = await fcmService.sendToDevice(device.fcm_token, {
        type: 'DECOUPLE_COMMAND',
        command: 'DECOUPLE',
        deviceId: device.id,
        deviceImei: device.imei || '',
        reason: 'DEALER_TEST_DECOUPLE',
        timestamp: signedCommand.timestamp ? String(signedCommand.timestamp) : Date.now().toString(),
        nonce: signedCommand.nonce,
        hmacSignature: signedCommand.hmacSignature || signedCommand.signature,
        serverId: process.env.SERVER_ID || 'server-001'
      });
    } catch (error) {
      warnOptionalFailure('test decouple FCM send', error);
      return res
        .status(502)
        .json(buildErrorResponse(502, 'FCM_SEND_FAILED', 'Could not send decouple command'));
    }

    if (!fcmResult?.success) {
      if (fcmResult?.invalidToken) {
        await db.query(
          `UPDATE devices
           SET fcm_token_status = 'invalid',
               app_uninstall_suspected_at = COALESCE(app_uninstall_suspected_at, NOW()),
               updated_at = NOW()
           WHERE id = $1`,
          [device.id]
        );
      }
      return res.status(502).json(
        buildErrorResponse(
          502,
          'FCM_DELIVERY_FAILED',
          fcmResult?.error || 'Decouple command was not accepted by FCM'
        )
      );
    }

    await db.query(
      `UPDATE devices
       SET status = 'pending_decouple',
           lock_level = 'NONE',
           lock_reason = NULL,
           locked_at = NULL,
           locked_by = NULL,
           updated_at = NOW()
       WHERE id = $1`,
      [device.id]
    );

    try {
      const sseService = require('../modules/sse/sseService');
      const payload = {
        deviceId: device.id,
        deviceName: device.device_name,
        status: 'pending_decouple',
        requestedAt: new Date().toISOString(),
        testMode: true
      };
      sseService.pushToDealer(dealer.id, 'device_decoupling_requested', payload);
      sseService.pushToManagement('device_decoupling_requested', payload);
    } catch (error) {
      warnOptionalFailure('test decouple SSE emit', error);
    }

    return res.json({
      success: true,
      status: 'pending_decouple',
      message: 'Test decouple command sent. Waiting for device heartbeat confirmation.',
      fcm: fcmResult
    });
  })
);

// ─── Location anomaly alerts ──────────────────────────────────────────────
// Dealers see anomaly alerts (unusual movement, SIM+location, impossible travel).
// Raw coordinates are NEVER returned here — only human-readable area descriptions.
// To see the exact location for one alert, dealer must submit a reveal request
// with a stated reason (logged permanently for legal accountability).

router.get(
  '/devices/:deviceId/anomalies',
  param('deviceId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    let anomalies = [];
    try {
      const result = await db.query(
        `SELECT id, alert_type, area_description, confidence, detected_at, dealer_viewed
         FROM location_anomalies
         WHERE device_id = $1
         ORDER BY detected_at DESC
         LIMIT 50`,
        [req.params.deviceId]
      );
      anomalies = result.rows;

      // Mark all as viewed
      await db.query(
        `UPDATE location_anomalies SET dealer_viewed = TRUE
         WHERE device_id = $1 AND dealer_viewed = FALSE`,
        [req.params.deviceId]
      );
    } catch (error) {
      warnOptionalFailure('location anomaly list lookup', error);
    }

    return res.json({ anomalies });
  })
);

router.post(
  '/devices/:deviceId/anomalies/:alertId/reveal',
  param('deviceId').isUUID(),
  param('alertId').isUUID(),
  body('reason').notEmpty().isString().isLength({ max: 500 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    const device = await db.query(
      'SELECT id FROM devices WHERE id = $1 AND dealer_id = ANY($2::uuid[])',
      [req.params.deviceId, dealerIds]
    );
    if (!device.rows.length)
      return res.status(404).json(buildErrorResponse(404, 'DEVICE_NOT_FOUND', 'Device not found'));

    let coordinate = null;
    try {
      const sessionExpires = new Date(Date.now() + 30 * 60 * 1000);

      // Log the reveal request (permanent audit trail)
      await db.query(
        `INSERT INTO location_reveal_log
           (anomaly_id, requested_by, requester_role, reason, session_expires)
         VALUES ($1, $2, 'dealer', $3, $4)`,
        [req.params.alertId, req.user.id, req.body.reason, sessionExpires]
      );

      // Fetch the single coordinate stored for this anomaly (if any)
      const coordRes = await db.query(
        `SELECT area_description, alert_type, detected_at,
                reveal_lat AS lat, reveal_lon AS lon
         FROM location_anomalies
         WHERE id = $1 AND device_id = $2`,
        [req.params.alertId, req.params.deviceId]
      );
      coordinate = coordRes.rows[0] || null;
    } catch (error) {
      warnOptionalFailure('location anomaly reveal', error);
    }

    return res.json({
      revealed: true,
      coordinate,
      session_expires_minutes: 30,
      note: 'This access has been permanently logged.'
    });
  })
);

// ─── Customer credit lookup ────────────────────────────────────────────────
// Dealer enters customer NID hash before approving a new EMI.
// Returns: credit tier + score + payment history summary.
// NEVER returns: which dealer previously sold a device, device model, purchase price.
// This protects trade practice — cross-dealer lookup is score-only.

router.post(
  '/customer/lookup',
  body('nid_hash')
    .notEmpty()
    .isString()
    .isLength({ min: 64, max: 64 })
    .withMessage('nid_hash must be a 64-character SHA-256 hex string'),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash } = req.body;

    let profile = null;
    let blacklisted = false;
    let blacklistReason = null;

    try {
      // Check blacklist first
      const blResult = await db.query(
        `SELECT reason FROM fraud_blacklist WHERE nid_hash = $1 AND active = TRUE`,
        [nid_hash]
      );
      if (blResult.rows.length) {
        blacklisted = true;
        blacklistReason = blResult.rows[0].reason;
      }

      // Fetch credit profile
      const cpResult = await db.query(
        `SELECT score, tier, member_since, devices_completed,
                installments_paid, installments_late, installments_missed,
                fraud_flags, sim_stability, last_activity_month
         FROM customer_credit_profiles
         WHERE nid_hash = $1`,
        [nid_hash]
      );
      profile = cpResult.rows[0] || null;
    } catch (_) {
      // Tables may not exist yet — treat as new customer
    }

    if (blacklisted) {
      return res.json({
        status: 'BLACKLISTED',
        reason: blacklistReason,
        recommendation: 'Do not proceed. Contact reseller for details.'
      });
    }

    if (!profile) {
      return res.json({
        status: 'NEW_MEMBER',
        score: null,
        tier: null,
        recommendation: 'No previous EMI history. Standard verification required.'
      });
    }

    const paymentRate =
      profile.installments_paid > 0
        ? Math.round(
            (profile.installments_paid /
              (profile.installments_paid +
                profile.installments_late +
                profile.installments_missed)) *
              100
          )
        : 100;

    return res.json({
      status: 'RETURNING_CUSTOMER',
      score: profile.score,
      tier: profile.tier,
      member_since: profile.member_since,
      devices_completed: profile.devices_completed,
      installments_paid: profile.installments_paid,
      payment_rate: paymentRate,
      fraud_flags: profile.fraud_flags,
      sim_stability: profile.sim_stability,
      last_activity_month: profile.last_activity_month,
      recommendation: getCreditRecommendation(profile.tier)
    });
  })
);

// ─── Profile seed registration ─────────────────────────────────────────────
// Dealer registers that they have stored a customer credit profile in their
// Google Drive. Server maintains index of who has which profile for fast lookup.

router.post(
  '/profiles/register-seed',
  body('nid_hash').notEmpty().isString().isLength({ min: 64, max: 64 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    if (!dealer)
      return res
        .status(404)
        .json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer profile not found'));

    try {
      await db.query(
        `INSERT INTO profile_seed_index (nid_hash, seed_type, seed_holder_id, last_synced_at)
         VALUES ($1, 'DEALER_DRIVE', $2, NOW())
         ON CONFLICT (nid_hash, seed_type, seed_holder_id) DO UPDATE
           SET last_synced_at = NOW()`,
        [req.body.nid_hash, req.user.id]
      );
    } catch (error) {
      warnOptionalFailure('profile seed registration', error);
    }

    return res.json({ registered: true });
  })
);

router.get(
  '/profiles/lookup-seed',
  asyncHandler(async (req, res) => {
    const nidHash = (req.query.nid_hash || '').trim();
    if (!nidHash || nidHash.length !== 64)
      return res
        .status(400)
        .json(
          buildErrorResponse(
            400,
            'INVALID_HASH',
            'nid_hash must be a 64-character SHA-256 hex string'
          )
        );

    let seeds = [];
    let scoreInfo = null;

    try {
      const seedRes = await db.query(
        `SELECT seed_type, seed_holder_id, last_synced_at
         FROM profile_seed_index WHERE nid_hash = $1
         ORDER BY last_synced_at DESC`,
        [nidHash]
      );
      seeds = seedRes.rows;

      const scoreRes = await db.query(
        `SELECT score, tier FROM customer_credit_profiles WHERE nid_hash = $1`,
        [nidHash]
      );
      scoreInfo = scoreRes.rows[0] || null;
    } catch (error) {
      warnOptionalFailure('profile seed lookup', error);
    }

    return res.json({ seeds, score: scoreInfo?.score || null, tier: scoreInfo?.tier || null });
  })
);

// ─── PADT pending list ─────────────────────────────────────────────────────

router.get(
  '/padt/pending',
  asyncHandler(async (req, res) => {
    const dealer = await getDealerProfile(req.user.id);
    const dealerIds = getDealerIds(req.user.id, dealer);

    // padt_tokens table may not exist if migration hasn't run — return empty gracefully
    let rows = [];
    try {
      const result = await db.query(
        `SELECT d.id, d.imei, d.model, d.brand, d.status,
              pt.expires_at, pt.used, pt.issued_at, pt.jti
       FROM devices d
       JOIN padt_tokens pt ON pt.device_id = d.id
       WHERE d.dealer_id = ANY($1::uuid[])
         AND pt.used    = false
         AND pt.revoked = false
         AND pt.expires_at > NOW()
       ORDER BY pt.issued_at DESC`,
        [dealerIds]
      );
      rows = result.rows;
    } catch (_) {
      // Table not yet migrated — return empty list, not an error
    }

    return res.json({ pending: rows });
  })
);

// ─── AMAPI Enrollment QR ───────────────────────────────────────────────────
// Returns a QR value string for Android setup-wizard Device Owner provisioning.
// The setup wizard downloads our signed APK, verifies the checksum, installs it,
// and sets DeviceAdminReceiver as the Device Policy Controller / Device Owner.
router.post(
  '/enrollment-qr',
  asyncHandler(async (req, res) => {
    const apkUrl = process.env.USER_APP_APK_URL || DEFAULT_USER_APP_APK_URL;
    const apkChecksum =
      process.env.USER_APP_APK_CHECKSUM || DEFAULT_USER_APP_APK_CHECKSUM;

    const provisioningPayload = {
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME': USER_APP_ADMIN_RECEIVER,
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION': apkUrl,
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM': apkChecksum,
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_MINIMUM_VERSION_CODE': 1,
      'android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED': true,
      'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': {
        api_base_url: process.env.PUBLIC_API_BASE_URL || process.env.API_BASE_URL || '',
        enrollment_source: 'dealer_app'
      }
    };

    return res.json({
      qr_value: JSON.stringify(provisioningPayload),
      token_name: 'self_hosted_user_app_device_owner',
      mode: 'self_hosted_device_owner',
      package_name: USER_APP_PACKAGE,
      apk_url: apkUrl,
      checksum: apkChecksum
    });
  })
);

module.exports = router;
