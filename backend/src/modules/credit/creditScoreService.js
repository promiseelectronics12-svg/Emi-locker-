const db = require('../../config/database');
const logger = require('../../utils/logger');

const SCORE_DELTAS = {
  ON_TIME_PAYMENT:    +50,
  LATE_PAYMENT:       -30,
  MISSED_PAYMENT:     -60,
  DEVICE_COMPLETED:   +100,
  FRAUD_CONFIRMED:    -600,
  SIM_CHANGE:         -40,
  ANOMALY_DETECTED:   -25,
  SIM_STABILITY_HIGH: +30,
  MANUAL_ADJUSTMENT:  0,   // delta provided by caller
};

function recalculateTier(score) {
  if (score >= 800) return 'GOLD';
  if (score >= 600) return 'SILVER';
  if (score >= 400) return 'BRONZE';
  if (score >= 200) return 'RED';
  return 'BLACKLISTED';
}

async function lookupByNidHash(nidHash) {
  const profile = await db.query(
    `SELECT score, tier, member_since, devices_completed,
            installments_paid, installments_late, installments_missed,
            fraud_flags, sim_stability, last_activity_month
     FROM customer_credit_profiles
     WHERE nid_hash = $1`,
    [nidHash]
  );

  if (profile.rows.length === 0) return null;

  const p = profile.rows[0];
  const total = p.installments_paid + p.installments_late + p.installments_missed;
  const payment_rate = total > 0
    ? Math.round((p.installments_paid / total) * 100)
    : null;

  return {
    score: p.score,
    tier: p.tier,
    member_since: p.member_since,
    devices_completed: p.devices_completed,
    installments_paid: p.installments_paid,
    installments_late: p.installments_late,
    installments_missed: p.installments_missed,
    payment_rate,
    fraud_flags: p.fraud_flags,
    sim_stability: p.sim_stability,
    last_activity_month: p.last_activity_month,
  };
}

async function recordPaymentEvent(nidHash, eventType, customDelta = null) {
  const delta = customDelta !== null ? customDelta : (SCORE_DELTAS[eventType] ?? 0);

  const currentMonth = new Date().toISOString().slice(0, 7); // YYYY-MM

  const upsertResult = await db.query(
    `INSERT INTO customer_credit_profiles (nid_hash, score, tier, last_activity_month)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (nid_hash) DO UPDATE SET
       score              = GREATEST(0, LEAST(1000, customer_credit_profiles.score + $5)),
       installments_paid  = CASE WHEN $6 = 'ON_TIME_PAYMENT'  THEN customer_credit_profiles.installments_paid  + 1 ELSE customer_credit_profiles.installments_paid  END,
       installments_late  = CASE WHEN $6 = 'LATE_PAYMENT'     THEN customer_credit_profiles.installments_late  + 1 ELSE customer_credit_profiles.installments_late  END,
       installments_missed= CASE WHEN $6 = 'MISSED_PAYMENT'   THEN customer_credit_profiles.installments_missed + 1 ELSE customer_credit_profiles.installments_missed END,
       devices_completed  = CASE WHEN $6 = 'DEVICE_COMPLETED' THEN customer_credit_profiles.devices_completed + 1 ELSE customer_credit_profiles.devices_completed END,
       fraud_flags        = CASE WHEN $6 = 'FRAUD_CONFIRMED'  THEN customer_credit_profiles.fraud_flags + 1 ELSE customer_credit_profiles.fraud_flags END,
       sim_stability      = CASE WHEN $6 = 'SIM_STABILITY_HIGH' THEN 'HIGH'
                                 WHEN $6 = 'SIM_CHANGE'         THEN 'LOW'
                                 ELSE customer_credit_profiles.sim_stability END,
       last_activity_month= $4,
       updated_at         = NOW()
     RETURNING score`,
    [
      nidHash,
      Math.max(0, Math.min(1000, 500 + delta)), // initial score for new profiles
      recalculateTier(500 + delta),
      currentMonth,
      delta,
      eventType,
    ]
  );

  const newScore = upsertResult.rows[0].score;
  const newTier  = recalculateTier(newScore);

  // Update tier after score change
  await db.query(
    `UPDATE customer_credit_profiles SET tier = $1 WHERE nid_hash = $2`,
    [newTier, nidHash]
  );

  // Permanent audit trail
  await db.query(
    `INSERT INTO credit_score_events (nid_hash, event_type, score_delta, score_after)
     VALUES ($1, $2, $3, $4)`,
    [nidHash, eventType, delta, newScore]
  );

  return { score: newScore, tier: newTier, delta };
}

async function checkBlacklist(nidHash) {
  const result = await db.query(
    `SELECT reason FROM fraud_blacklist WHERE nid_hash = $1 AND active = TRUE`,
    [nidHash]
  );

  if (result.rows.length === 0) return { blacklisted: false };
  return { blacklisted: true, reason: result.rows[0].reason };
}

module.exports = { lookupByNidHash, recordPaymentEvent, recalculateTier, checkBlacklist };
