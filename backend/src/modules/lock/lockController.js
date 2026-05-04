const asyncHandler = require('express-async-handler');
const lockService = require('./lockService');
const pautService = require('./pautService');
const padtService = require('./padtService');
const logger = require('../../utils/logger');

const requestLock = asyncHandler(async (req, res) => {
  const { deviceId, reason, note } = req.body;
  const dealerId = req.user.id;

  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId is required' });
  }

  if (!reason) {
    return res.status(400).json({ error: 'reason is required' });
  }

  const validReasons = ['EMI_OVERDUE', 'SUSPECTED_FRAUD', 'SUSPECTED_SALE', 'DEVICE_STOLEN', 'TERMS_VIOLATION'];
  if (!validReasons.includes(reason)) {
    return res.status(400).json({
      error: 'Invalid reason code',
      validReasons,
    });
  }

  if (note && note.length > 200) {
    return res.status(400).json({ error: 'Note must be 200 characters or less' });
  }

  try {
    const result = await lockService.requestLock({ deviceId, dealerId, reason, note });

    const statusCode = result.status === 'APPROVED' ? 200 : 422;

    logger.info('Lock request processed', {
      dealerId,
      deviceId,
      reason,
      decision: result.decision,
    });

    res.status(statusCode).json({
      success: result.status === 'APPROVED',
      data: result,
    });
  } catch (error) {
    logger.error('Lock request failed', { dealerId, deviceId, error: error.message });
    res.status(500).json({ error: 'Lock request processing failed' });
  }
});

const generateCommand = asyncHandler(async (req, res) => {
  const { deviceImei, actionType, lockLevel, metadata } = req.body;

  if (!deviceImei) {
    return res.status(400).json({ error: 'deviceImei is required' });
  }

  if (!actionType) {
    return res.status(400).json({ error: 'actionType is required' });
  }

  try {
    const command = await lockService.generateCommand({
      deviceImei,
      actionType,
      lockLevel,
      metadata,
    });

    res.status(201).json({
      success: true,
      data: command,
    });
  } catch (error) {
    logger.error('Command generation failed', { deviceImei, error: error.message });
    res.status(500).json({ error: 'Command generation failed' });
  }
});

const issuePaut = asyncHandler(async (req, res) => {
  const { deviceId, imei, lockLevel } = req.body;

  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId is required' });
  }

  try {
    const result = await lockService.issuePaut({ deviceId, imei, lockLevel });

    res.status(201).json({
      success: true,
      data: result,
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: error.message });
    }
    logger.error('PAUT issuance failed', { deviceId, error: error.message });
    res.status(500).json({ error: 'PAUT issuance failed' });
  }
});

const issuePadt = asyncHandler(async (req, res) => {
  const { deviceId, imei, ownerId, dealerId } = req.body;

  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId is required' });
  }

  try {
    const result = await lockService.issuePadt({ deviceId, imei, ownerId, dealerId });

    res.status(201).json({
      success: true,
      data: result,
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: error.message });
    }
    logger.error('PADT issuance failed', { deviceId, error: error.message });
    res.status(500).json({ error: 'PADT issuance failed' });
  }
});

const getDeviceLockStatus = asyncHandler(async (req, res) => {
  const { id } = req.params;

  try {
    const status = await lockService.getDeviceLockStatus(id);

    res.json({
      success: true,
      data: status,
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: error.message });
    }
    logger.error('Failed to get device lock status', { deviceId: id, error: error.message });
    res.status(500).json({ error: 'Failed to retrieve device lock status' });
  }
});

const getDealerLockRequests = asyncHandler(async (req, res) => {
  const dealerId = req.user.id;
  const page = parseInt(req.query.page, 10) || 1;
  const limit = parseInt(req.query.limit, 10) || 20;

  try {
    const result = await lockService.getDealerLockRequests(dealerId, { page, limit });

    res.json({
      success: true,
      data: result,
    });
  } catch (error) {
    logger.error('Failed to get dealer lock requests', { dealerId, error: error.message });
    res.status(500).json({ error: 'Failed to retrieve lock requests' });
  }
});

const verifyPaut = asyncHandler(async (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'token is required' });
  }

  const result = await pautService.verifyToken(token);

  res.json({
    success: result.valid,
    data: result,
  });
});

const verifyAndConsumePaut = asyncHandler(async (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'token is required' });
  }

  const result = await pautService.verifyAndConsumeToken(token);

  res.json({
    success: result.consumed,
    data: result,
  });
});

const verifyPadt = asyncHandler(async (req, res) => {
  const { token } = req.body;

  if (!token) {
    return res.status(400).json({ error: 'token is required' });
  }

  const result = await padtService.verifyToken(token);

  res.json({
    success: result.valid,
    data: result,
  });
});

const requestUnlock = asyncHandler(async (req, res) => {
  const { deviceId } = req.body;
  const actorId = req.user.id;
  const actorRole = req.user.role;

  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId is required' });
  }

  try {
    const result = await lockService.requestUnlock({ deviceId, actorId, actorRole });

    const statusCode = result.status === 'APPROVED' ? 200 : 200;

    logger.info('Unlock request processed', {
      actorId,
      deviceId,
      decision: result.decision,
    });

    res.status(statusCode).json({
      success: result.status === 'APPROVED',
      data: result,
    });
  } catch (error) {
    logger.error('Unlock request failed', { actorId, deviceId, error: error.message });
    res.status(500).json({ error: 'Unlock request processing failed' });
  }
});

const revokePaut = asyncHandler(async (req, res) => {
  const { jti } = req.body;

  if (!jti) {
    return res.status(400).json({ error: 'jti is required' });
  }

  try {
    await pautService.revokeToken(jti);
    res.json({ success: true, data: { jti, revoked: true } });
  } catch (error) {
    logger.error('PAUT revoke failed', { jti, error: error.message });
    res.status(500).json({ error: 'Token revocation failed' });
  }
});

const revokePadt = asyncHandler(async (req, res) => {
  const { jti } = req.body;

  if (!jti) {
    return res.status(400).json({ error: 'jti is required' });
  }

  try {
    await padtService.revokeToken(jti);
    res.json({ success: true, data: { jti, revoked: true } });
  } catch (error) {
    logger.error('PADT revoke failed', { jti, error: error.message });
    res.status(500).json({ error: 'Token revocation failed' });
  }
});

module.exports = {
  requestLock,
  generateCommand,
  issuePaut,
  issuePadt,
  getDeviceLockStatus,
  getDealerLockRequests,
  verifyPaut,
  verifyAndConsumePaut,
  verifyPadt,
  requestUnlock,
  revokePaut,
  revokePadt,
};
