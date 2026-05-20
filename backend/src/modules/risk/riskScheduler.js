const cron = require('node-cron');
const logger = require('../../utils/logger');
const riskModel = require('./riskModel');
const riskService = require('./riskService');

let simScoringTask = null;
let lockEvalTask = null;

function initRiskScheduler() {
  logger.info('[RiskEngine] Initializing risk scheduler');

  // Every 3 min: recompute time-escalating signal weights (SIM missing, heartbeat missing)
  simScoringTask = cron.schedule('*/3 * * * *', async () => {
    try {
      await _runSignalRescoring();
    } catch (err) {
      logger.error('[RiskEngine] Signal rescoring failed', { error: err.message });
    }
  });

  // Every 5 min: evaluate auto-lock decisions for devices with score >= 3 or overdue
  lockEvalTask = cron.schedule('*/5 * * * *', async () => {
    try {
      await _runLockEvaluation();
    } catch (err) {
      logger.error('[RiskEngine] Lock evaluation failed', { error: err.message });
    }
  });

  logger.info('[RiskEngine] Risk scheduler started');
}

function stopRiskScheduler() {
  simScoringTask?.stop();
  lockEvalTask?.stop();
  logger.info('[RiskEngine] Risk scheduler stopped');
}

function isActive() {
  return simScoringTask !== null && lockEvalTask !== null;
}

// ── SIM missing: update time-escalating weight ───────────────────────────────
// This replaces the old runSimMissingCheck() which directly locked on SIM missing > 5 min.
// Now SIM missing is a risk signal only — lock requires compound rule.

async function _runSignalRescoring() {
  await _rescore_simMissing();
  await _rescore_heartbeatMissing();
}

async function _rescore_simMissing() {
  const devices = await riskModel.getDevicesWithSimMissing();
  for (const device of devices) {
    try {
      const since = new Date(device.sim_missing_since);
      const minutesMissing = (Date.now() - since.getTime()) / 60000;
      const weight = riskModel.simMissingWeight(minutesMissing);
      if (weight === 0) continue;
      await riskService.recordSignal(device.id, 'sim_missing', {
        since: device.sim_missing_since,
        minutesMissing: Math.round(minutesMissing),
      });
    } catch (err) {
      logger.error('[RiskEngine] SIM signal update failed', { deviceId: device.id, error: err.message });
    }
  }
}

// Fix #8: detect and clear heartbeat-missing signals
async function _rescore_heartbeatMissing() {
  // Record for devices silent > 24h
  const missingDevices = await riskModel.getDevicesWithHeartbeatMissing();
  for (const device of missingDevices) {
    try {
      const lastSeen = device.last_seen_at ? new Date(device.last_seen_at) : new Date(0);
      const minutesMissing = (Date.now() - lastSeen.getTime()) / 60000;
      await riskService.recordSignal(device.id, 'heartbeat_missing', {
        since: device.last_seen_at || null,
        minutesMissing: Math.round(minutesMissing),
      });
    } catch (err) {
      logger.error('[RiskEngine] Heartbeat signal update failed', { deviceId: device.id, error: err.message });
    }
  }

  // Clear for devices that resumed heartbeat
  const resumedDevices = await riskModel.getDevicesWithHeartbeatResumed();
  for (const device of resumedDevices) {
    try {
      await riskService.removeSignal(device.id, 'heartbeat_missing');
    } catch (err) {
      logger.error('[RiskEngine] Heartbeat clear failed', { deviceId: device.id, error: err.message });
    }
  }
}

// ── Lock evaluation: check compound rule for at-risk devices ─────────────────

async function _runLockEvaluation() {
  const overdueDevices = await riskModel.getOverdueActiveDevices();
  if (!overdueDevices.length) return;

  for (const device of overdueDevices) {
    try {
      await riskService.evaluateLockDecision(device.id);
    } catch (err) {
      logger.error('[RiskEngine] Lock evaluation failed for device', { deviceId: device.id, error: err.message });
    }
  }
}

module.exports = {
  initRiskScheduler,
  stopRiskScheduler,
  isActive,
  _runSignalRescoring,
  _runLockEvaluation,
};
