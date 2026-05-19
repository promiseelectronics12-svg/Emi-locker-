const db = require('../../config/database');

// ── Signal weights (static) ─────────────────────────────────────────────────

const STATIC_WEIGHTS = {
  emi_locker_admin_revoked: 3,
  gmail_mismatch: 2,
  boot_after_shutdown: 1,
};

function simMissingWeight(minutesMissing) {
  if (minutesMissing < 5) return 0;
  if (minutesMissing < 120) return 4;
  if (minutesMissing < 1440) return 6;
  return 8;
}

function heartbeatMissingWeight(minutesMissing) {
  if (minutesMissing < 1440) return 4;
  if (minutesMissing < 2880) return 6;
  return 8;
}

// ── Read ────────────────────────────────────────────────────────────────────

async function getScore(deviceId) {
  const result = await db.query(
    `SELECT total_score, signals, dealer_notified_at, updated_at
     FROM device_risk_scores WHERE device_id = $1`,
    [deviceId]
  );
  return result.rows[0] || { total_score: 0, signals: {}, dealer_notified_at: null };
}

async function getSignalHistory(deviceId, limit = 50) {
  const result = await db.query(
    `SELECT signal_type, weight, action, details, created_at
     FROM risk_signal_log
     WHERE device_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [deviceId, limit]
  );
  return result.rows;
}

async function getDecisionHistory(deviceId, limit = 20) {
  const result = await db.query(
    `SELECT is_overdue, risk_score, signal_breakdown, dealer_notified_at,
            window_expires_at, window_expired, decision, notes, evaluated_at
     FROM auto_lock_decisions
     WHERE device_id = $1
     ORDER BY evaluated_at DESC LIMIT $2`,
    [deviceId, limit]
  );
  return result.rows;
}

// ── Write ───────────────────────────────────────────────────────────────────

async function upsertSignal(deviceId, signalType, weight, details = {}) {
  const existing = await getScore(deviceId);
  const signals = { ...existing.signals };

  const prev = signals[signalType];
  const action = prev ? 'escalated' : 'recorded';

  signals[signalType] = {
    weight,
    since: prev?.since || new Date().toISOString(),
    details,
  };

  const totalScore = Object.values(signals).reduce((sum, s) => sum + s.weight, 0);

  await db.query(
    `INSERT INTO device_risk_scores (device_id, total_score, signals, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (device_id) DO UPDATE
       SET total_score = $2, signals = $3, updated_at = NOW()`,
    [deviceId, totalScore, JSON.stringify(signals)]
  );

  await db.query(
    `INSERT INTO risk_signal_log (device_id, signal_type, weight, action, details)
     VALUES ($1, $2, $3, $4, $5)`,
    [deviceId, signalType, weight, action, JSON.stringify(details)]
  );

  return { totalScore, signals, action };
}

async function clearSignal(deviceId, signalType) {
  const existing = await getScore(deviceId);
  if (!existing.signals[signalType]) return null;

  const signals = { ...existing.signals };
  const cleared = signals[signalType];
  delete signals[signalType];

  const totalScore = Object.values(signals).reduce((sum, s) => sum + s.weight, 0);

  await db.query(
    `INSERT INTO device_risk_scores (device_id, total_score, signals, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (device_id) DO UPDATE
       SET total_score = $2, signals = $3, updated_at = NOW()`,
    [deviceId, totalScore, JSON.stringify(signals)]
  );

  await db.query(
    `INSERT INTO risk_signal_log (device_id, signal_type, weight, action, details)
     VALUES ($1, $2, $3, 'cleared', $4)`,
    [deviceId, signalType, cleared.weight, JSON.stringify({ reason: 'signal_resolved' })]
  );

  return { totalScore, signals };
}

async function setDealerNotifiedAt(deviceId) {
  const result = await db.query(
    `UPDATE device_risk_scores
     SET dealer_notified_at = COALESCE(dealer_notified_at, NOW())
     WHERE device_id = $1
     RETURNING dealer_notified_at`,
    [deviceId]
  );
  return result.rows[0]?.dealer_notified_at || null;
}

// Fix #7: reset dealer window when risk episode resolves (score drops below threshold)
async function resetDealerNotifiedAt(deviceId) {
  await db.query(
    `UPDATE device_risk_scores SET dealer_notified_at = NULL
     WHERE device_id = $1`,
    [deviceId]
  );
}

async function logDecision(deviceId, {
  isOverdue, riskScore, signalBreakdown,
  dealerNotifiedAt, windowExpiresAt, windowExpired, decision, notes
}) {
  await db.query(
    `INSERT INTO auto_lock_decisions
       (device_id, is_overdue, risk_score, signal_breakdown,
        dealer_notified_at, window_expires_at, window_expired, decision, notes)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      deviceId, isOverdue, riskScore,
      JSON.stringify(signalBreakdown),
      dealerNotifiedAt, windowExpiresAt, windowExpired, decision, notes || null
    ]
  );
}

// ── Device queries used by scheduler ────────────────────────────────────────

async function getDevicesWithSimMissing() {
  const result = await db.query(
    `SELECT d.id, d.dealer_id, d.device_name, d.imei, d.sim_missing_since
     FROM devices d
     WHERE d.sim_missing_since IS NOT NULL
       AND d.status NOT IN ('locked','fraud_suspected','decoupled',
                            'decommissioned','disabled','suspended','pending')
     ORDER BY d.sim_missing_since ASC`
  );
  return result.rows;
}

// Fix #8: heartbeat missing detection (24h normal tolerance)
async function getDevicesWithHeartbeatMissing() {
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const result = await db.query(
    `SELECT d.id, d.dealer_id, d.last_seen_at
     FROM devices d
     WHERE (d.last_seen_at IS NULL OR d.last_seen_at < $1)
       AND d.status NOT IN ('locked','fraud_suspected','decoupled',
                            'decommissioned','disabled','suspended','pending')
       AND EXISTS (
         SELECT 1 FROM emi_schedules es
         WHERE es.device_id = d.id AND es.status = 'active'
       )`,
    [cutoff]
  );
  return result.rows;
}

// Devices whose heartbeat has resumed (within last 15 min) but still have a heartbeat_missing signal
async function getDevicesWithHeartbeatResumed() {
  const resumedCutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const result = await db.query(
    `SELECT d.id FROM devices d
     INNER JOIN device_risk_scores drs ON drs.device_id = d.id
     WHERE d.last_seen_at >= $1
       AND drs.signals ? 'heartbeat_missing'`,
    [resumedCutoff]
  );
  return result.rows;
}

async function getOverdueActiveDevices() {
  const result = await db.query(
    `WITH active_schedules AS (
       SELECT DISTINCT ON (es.device_id)
              es.id,
              es.device_id,
              es.start_date,
              es.emi_amount,
              es.duration,
              es.grace_days,
              es.down_payment,
              COALESCE((
                SELECT SUM(ep.amount)
                FROM emi_payments ep
                WHERE ep.emi_schedule_id = es.id
                  AND ep.payment_status = 'completed'
              ), 0) AS total_paid
       FROM emi_schedules es
       WHERE es.status = 'active'
       ORDER BY es.device_id, es.created_at DESC
     ),
     overdue_devices AS (
       SELECT a.device_id
       FROM active_schedules a
       CROSS JOIN LATERAL (
         SELECT cd.due_date,
                ROW_NUMBER() OVER (ORDER BY cd.due_date) AS installment_number
         FROM calculate_due_dates(a.device_id, a.start_date, a.emi_amount, a.duration) cd
       ) inst
       WHERE a.total_paid < (COALESCE(a.down_payment, 0) + inst.installment_number * a.emi_amount)
         AND CURRENT_DATE > (inst.due_date + (COALESCE(a.grace_days, 0) || ' days')::interval)::date
       GROUP BY a.device_id
     )
     SELECT d.id, d.dealer_id, d.device_name, d.imei, d.last_seen_at, d.status
     FROM devices d
     INNER JOIN overdue_devices od ON od.device_id = d.id
     WHERE d.status NOT IN ('locked','fraud_suspected','decoupled',
                            'decommissioned','disabled','suspended')`
  );
  return result.rows;
}

module.exports = {
  STATIC_WEIGHTS,
  simMissingWeight,
  heartbeatMissingWeight,
  getScore,
  getSignalHistory,
  getDecisionHistory,
  upsertSignal,
  clearSignal,
  setDealerNotifiedAt,
  resetDealerNotifiedAt,
  logDecision,
  getDevicesWithSimMissing,
  getDevicesWithHeartbeatMissing,
  getDevicesWithHeartbeatResumed,
  getOverdueActiveDevices,
};
