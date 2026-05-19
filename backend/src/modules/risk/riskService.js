const db = require('../../config/database');
const logger = require('../../utils/logger');
const riskModel = require('./riskModel');
const sseService = require('../sse/sseService');
const dealerNotificationService = require('../notifications/dealerNotificationService');

const DEALER_WINDOW_MS = 2 * 60 * 60 * 1000; // 2 hours
const SCORE_THRESHOLD = 6;

// ── Signal recording ─────────────────────────────────────────────────────────

async function recordSignal(deviceId, signalType, details = {}) {
  let weight;

  if (signalType === 'sim_missing') {
    const since = details.since ? new Date(details.since) : new Date();
    const minutesMissing = (Date.now() - since.getTime()) / 60000;
    weight = riskModel.simMissingWeight(minutesMissing);
    if (weight === 0) return null;
  } else if (signalType === 'heartbeat_missing') {
    const since = details.since ? new Date(details.since) : new Date();
    const minutesMissing = (Date.now() - since.getTime()) / 60000;
    weight = riskModel.heartbeatMissingWeight(minutesMissing);
  } else {
    // Pending wiring: emi_locker_admin_revoked, gmail_mismatch, boot_after_shutdown
    // These are triggered via POST /risk/:deviceId/signal (admin) or future app events.
    weight = riskModel.STATIC_WEIGHTS[signalType];
    if (weight === undefined) {
      logger.warn('[RiskEngine] Unknown signal type', { deviceId, signalType });
      return null;
    }
  }

  const result = await riskModel.upsertSignal(deviceId, signalType, weight, details);

  logger.info('[RiskEngine] Signal recorded', {
    deviceId, signalType, weight, action: result.action, totalScore: result.totalScore
  });

  await _emitScoreChanged(deviceId, result);
  return result;
}

async function removeSignal(deviceId, signalType) {
  const result = await riskModel.clearSignal(deviceId, signalType);
  if (!result) return null;

  logger.info('[RiskEngine] Signal cleared', { deviceId, signalType, totalScore: result.totalScore });

  // Fix #7: reset dealer window when score drops below threshold after signal resolved
  if (result.totalScore < SCORE_THRESHOLD) {
    await riskModel.resetDealerNotifiedAt(deviceId);
  }

  await _emitScoreChanged(deviceId, result);
  return result;
}

// ── Lock decision evaluation ─────────────────────────────────────────────────
// Single rule: overdue_emi && risk_score >= 6 && dealer_notification_window_expired
// Never locks on a single signal. Every evaluation is audited.

async function evaluateLockDecision(deviceId) {
  const [scoreRow, overdueRow, deviceRow] = await Promise.all([
    riskModel.getScore(deviceId),
    _getOverdueStatus(deviceId),
    _getDeviceRow(deviceId),
  ]);

  const riskScore = scoreRow.total_score;
  const signalBreakdown = scoreRow.signals;
  const isOverdue = overdueRow.isOverdue;
  const dealerNotifiedAt = scoreRow.dealer_notified_at;
  let effectiveDealerNotifiedAt = dealerNotifiedAt;
  let windowExpiresAt = dealerNotifiedAt
    ? new Date(new Date(dealerNotifiedAt).getTime() + DEALER_WINDOW_MS).toISOString()
    : null;
  const windowExpired = dealerNotifiedAt
    ? Date.now() - new Date(dealerNotifiedAt).getTime() >= DEALER_WINDOW_MS
    : false;

  // Fix #3: audit every evaluation including already-locked, before returning
  const isAlreadyLocked = !deviceRow
    || ['locked', 'fraud_suspected', 'decoupled',
        'decommissioned', 'disabled', 'suspended'].includes(deviceRow.status);

  if (isAlreadyLocked) {
    await riskModel.logDecision(deviceId, {
      isOverdue, riskScore, signalBreakdown: signalBreakdown || {},
      dealerNotifiedAt: effectiveDealerNotifiedAt,
      windowExpiresAt,
      windowExpired,
      decision: 'already_locked',
      notes: `Device status: ${deviceRow?.status ?? 'not_found'}`,
    });
    return { decision: 'already_locked', riskScore, isOverdue };
  }

  let decision;
  let notes = null;

  if (!isOverdue) {
    decision = 'not_overdue';
    notes = `Risk score ${riskScore}. No overdue payment.`;
  } else if (riskScore < SCORE_THRESHOLD) {
    decision = 'score_insufficient';
    notes = `Overdue but risk score ${riskScore} < ${SCORE_THRESHOLD}. Single signals never lock.`;
  } else if (!windowExpired) {
    decision = 'pending_dealer_window';
    notes = `Overdue + score ${riskScore} >= ${SCORE_THRESHOLD}. Dealer window not expired.`;
    // Fix #2: only notify once per risk episode (pass existingNotifiedAt)
    const notificationWindow = await _ensureDealerNotified(
      deviceId,
      deviceRow,
      riskScore,
      signalBreakdown,
      dealerNotifiedAt
    );
    effectiveDealerNotifiedAt = notificationWindow.dealerNotifiedAt;
    windowExpiresAt = notificationWindow.windowExpiresAt;
  } else {
    decision = 'locked';
    await _executeAutoLock(deviceId, deviceRow, riskScore, signalBreakdown);
  }

  await riskModel.logDecision(deviceId, {
    isOverdue, riskScore, signalBreakdown,
    dealerNotifiedAt: effectiveDealerNotifiedAt,
    windowExpiresAt,
    windowExpired,
    decision,
    notes
  });

  logger.info('[RiskEngine] Lock decision', { deviceId, decision, riskScore, isOverdue, windowExpired });
  return { decision, riskScore, isOverdue, windowExpired };
}

// ── Read API ─────────────────────────────────────────────────────────────────

async function getScoreWithHistory(deviceId) {
  const [score, signals, decisions] = await Promise.all([
    riskModel.getScore(deviceId),
    riskModel.getSignalHistory(deviceId, 50),
    riskModel.getDecisionHistory(deviceId, 20),
  ]);
  return { score, signalHistory: signals, decisionHistory: decisions };
}

// ── Internal helpers ─────────────────────────────────────────────────────────

async function _getOverdueStatus(deviceId) {
  const result = await db.query(
    `WITH active_schedule AS (
       SELECT es.id,
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
       WHERE es.device_id = $1
         AND es.status = 'active'
       ORDER BY es.created_at DESC
       LIMIT 1
     ),
     installments AS (
       SELECT a.*,
              cd.due_date,
              ROW_NUMBER() OVER (ORDER BY cd.due_date) AS installment_number
       FROM active_schedule a
       CROSS JOIN LATERAL calculate_due_dates(a.device_id, a.start_date, a.emi_amount, a.duration) cd
     )
     SELECT COUNT(*) AS cnt
     FROM installments
     WHERE total_paid < (COALESCE(down_payment, 0) + installment_number * emi_amount)
       AND CURRENT_DATE > (due_date + (COALESCE(grace_days, 0) || ' days')::interval)::date`,
    [deviceId]
  );
  return { isOverdue: parseInt(result.rows[0]?.cnt || 0, 10) > 0 };
}

async function _getDeviceRow(deviceId) {
  const result = await db.query(
    `SELECT id, dealer_id, device_name, imei, status FROM devices WHERE id = $1`,
    [deviceId]
  );
  return result.rows[0] || null;
}

// Fix #2: only sends push/SSE on first notification per risk episode.
async function _ensureDealerNotified(deviceId, device, riskScore, signalBreakdown, existingNotifiedAt) {
  if (existingNotifiedAt) {
    // Already notified — do not spam. Decision row will record pending_dealer_window.
    const windowExpiresAt = new Date(
      new Date(existingNotifiedAt).getTime() + DEALER_WINDOW_MS
    ).toISOString();
    return { dealerNotifiedAt: existingNotifiedAt, windowExpiresAt };
  }

  const notifiedAt = await riskModel.setDealerNotifiedAt(deviceId);
  const dealerNotifiedAt = notifiedAt
    ? new Date(notifiedAt).toISOString()
    : new Date().toISOString();
  const windowExpiresAt = new Date(
    new Date(dealerNotifiedAt).getTime() + DEALER_WINDOW_MS
  ).toISOString();

  logger.info('[RiskEngine] Dealer notified — 2h window started', {
    deviceId, riskScore, signals: Object.keys(signalBreakdown)
  });

  if (!device.dealer_id) return { dealerNotifiedAt, windowExpiresAt };

  sseService.pushToDealer(device.dealer_id, 'risk_score_threshold', {
    deviceId,
    deviceName: device.device_name,
    imei: device.imei,
    riskScore,
    signalBreakdown,
    windowExpiresAt,
    message: `Device overdue + risk score ${riskScore}. Auto-lock in 2 hours if not resolved.`,
  });

  // Fix #1: call real method — no optional chaining that silently drops Promise
  dealerNotificationService.notifyRiskThreshold(device, riskScore, signalBreakdown, windowExpiresAt)
    .catch((err) => logger.warn('[RiskEngine] dealer risk push failed', { deviceId, error: err.message }));

  return { dealerNotifiedAt, windowExpiresAt };
}

// Fix #4: use signed command pipeline via LockService.requestAutoLock
// Fix #5: DB lock_level = 'FULL', command lockLevel = 'FULL_LOCK'
async function _executeAutoLock(deviceId, device, riskScore, signalBreakdown) {
  const lockService = require('../lock/lockService');
  const { getActiveAssignment } = require('../assignments/assignmentService');

  await lockService.requestAutoLock({
    deviceId,
    reason: 'AUTO_LOCK_RISK_ENGINE',
    riskScore,
    signalBreakdown,
  });

  const assignmentId = await getActiveAssignment(deviceId).catch(() => null);
  await db.query(
    `INSERT INTO device_history (device_id, assignment_id, event_type, actor_type, permanent, details)
     VALUES ($1, $2, 'LOCKED', 'system', false, $3)`,
    [
      deviceId, assignmentId,
      JSON.stringify({
        reason: 'AUTO_LOCK_RISK_ENGINE',
        lock_level: 'FULL',
        risk_score: riskScore,
        signals: Object.keys(signalBreakdown),
      })
    ]
  );

  logger.info('[RiskEngine] Auto-lock executed via signed command', {
    deviceId, riskScore, signals: Object.keys(signalBreakdown)
  });
}

// Fix #9: look up dealer_id before emitting SSE
async function _emitScoreChanged(deviceId, scoreData) {
  try {
    const row = await db.query(
      `SELECT dealer_id FROM devices WHERE id = $1`,
      [deviceId]
    );
    const dealerId = row.rows[0]?.dealer_id ?? null;
    sseService.emitRiskScoreChanged({ id: deviceId, dealer_id: dealerId }, scoreData);
  } catch (_) {}
}

module.exports = {
  recordSignal,
  removeSignal,
  evaluateLockDecision,
  getScoreWithHistory,
};
