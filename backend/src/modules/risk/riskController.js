const riskService = require('./riskService');

async function getScore(req, res) {
  const { deviceId } = req.params;
  const data = await riskService.getScoreWithHistory(deviceId);
  res.json(data);
}

async function recordSignal(req, res) {
  const { deviceId } = req.params;
  const { signalType, details } = req.body;

  if (!signalType) {
    return res.status(400).json({ error: 'signalType required' });
  }

  const result = await riskService.recordSignal(deviceId, signalType, details || {});
  if (!result) {
    return res.status(400).json({ error: 'Unknown or zero-weight signal' });
  }
  res.json(result);
}

async function clearSignal(req, res) {
  const { deviceId, signalType } = req.params;
  const result = await riskService.removeSignal(deviceId, signalType);
  if (!result) {
    return res.status(404).json({ error: 'Signal not active' });
  }
  res.json(result);
}

async function evaluateLock(req, res) {
  const { deviceId } = req.params;
  const result = await riskService.evaluateLockDecision(deviceId);
  res.json(result);
}

module.exports = { getScore, recordSignal, clearSignal, evaluateLock };
