const asyncHandler = require('express-async-handler');
const decouplingService = require('./decouplingService');
const logger = require('../../utils/logger');

// ============================================================
// GET /decoupling/:deviceId/status
// ============================================================
const getStatus = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  const status = await decouplingService.getDecouplingStatus(deviceId);
  if (!status) {
    return res.status(404).json({ error: 'No decoupling process found for this device' });
  }

  res.json({ success: true, data: status });
});

// ============================================================
// GET /decoupling/:deviceId/audit
// ============================================================
const getAuditTrail = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  const auditLogs = await decouplingService.getAuditTrail(deviceId);

  res.json({ success: true, data: { deviceId, auditLogs } });
});

// ============================================================
// POST /decoupling/:deviceId/fraud-flag
// Dealer flags fraud with written evidence.
// Dealer CAN: flag with written evidence.
// Dealer CANNOT: block or delay decoupling.
// ============================================================
const flagFraud = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { reason, evidenceUrl } = req.body;
  const dealerId = req.user.id;

  if (!reason || reason.trim().length < 10) {
    return res.status(400).json({ error: 'Fraud reason is required (minimum 10 characters)' });
  }

  try {
    const result = await decouplingService.flagFraud(deviceId, dealerId, reason, evidenceUrl);

    logger.warn(`Fraud flagged for device ${deviceId} by dealer ${dealerId}`);

    res.json({
      success: true,
      message: 'Fraud flag raised. Admin review will be triggered. This does NOT block decoupling.',
      data: {
        deviceId,
        fraudFlagged: result.fraud_flag,
        flaggedAt: result.fraud_flagged_at,
        reason: result.fraud_reason,
        note: 'Dealer approval is NOT required for decoupling. Admin will review this flag.',
      },
    });
  } catch (error) {
    if (error.message.includes('only be flagged during')) {
      return res.status(400).json({ error: error.message });
    }
    if (error.message.includes('window has expired')) {
      return res.status(400).json({ error: error.message });
    }
    if (error.message.includes('written reason')) {
      return res.status(400).json({ error: error.message });
    }
    if (error.message.includes('Only the assigned dealer')) {
      return res.status(403).json({ error: error.message });
    }
    logger.error('Fraud flag failed:', error);
    res.status(500).json({ error: 'Failed to flag fraud' });
  }
});

// ============================================================
// POST /decoupling/:deviceId/confirm-fraud
// ADMIN ONLY — confirms fraud investigation
// ============================================================
const confirmFraud = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const adminId = req.user.id;

  try {
    const result = await decouplingService.confirmFraud(deviceId, adminId);

    res.json({
      success: true,
      message: 'Fraud confirmed. Decoupling is blocked pending investigation.',
      data: {
        deviceId,
        state: result.state,
        confirmedAt: result.fraud_confirmed_at,
      },
    });
  } catch (error) {
    if (error.message.includes('FRAUD_FLAGGED state')) {
      return res.status(400).json({ error: error.message });
    }
    logger.error('Fraud confirm failed:', error);
    res.status(500).json({ error: 'Failed to confirm fraud' });
  }
});

// ============================================================
// POST /decoupling/:deviceId/reject-fraud
// ADMIN ONLY — rejects fraud, decoupling proceeds
// ============================================================
const rejectFraud = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const adminId = req.user.id;

  try {
    const result = await decouplingService.rejectFraud(deviceId, adminId);

    res.json({
      success: true,
      message: 'Fraud flag rejected. Decoupling will proceed.',
      data: {
        deviceId,
        state: result.state,
        rejectedAt: result.fraud_rejected_at,
      },
    });
  } catch (error) {
    if (error.message.includes('FRAUD_FLAGGED state')) {
      return res.status(400).json({ error: error.message });
    }
    logger.error('Fraud reject failed:', error);
    res.status(500).json({ error: 'Failed to reject fraud' });
  }
});

// ============================================================
// POST /decoupling/:deviceId/execute
// ADMIN ONLY — requires 2FA
// Generates RTOC, sends Decouple Command via FCM,
// calls AMAPI to delete managed account, marks DECOUPLED
// ============================================================
const executeDecoupling = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { totpCode } = req.body;
  const adminId = req.user.id;

  if (!totpCode) {
    return res.status(400).json({ error: '2FA code (totpCode) is required to execute decoupling' });
  }

  try {
    const result = await decouplingService.executeDecoupling(deviceId, adminId, totpCode);

    logger.info(`Decoupling executed for device ${deviceId} by admin ${adminId}`);

    res.json({
      success: true,
      message: 'Device has been successfully decoupled. All restrictions lifted.',
      data: {
        success: true,
        deviceId,
        fcmDelivered: result.fcmDelivered,
        amapiDeleted: result.amapiDeleted,
        decoupledAt: result.decoupledAt,
      },
    });
  } catch (error) {
    if (error.message.includes('already decoupled')) {
      return res.status(409).json({ error: error.message });
    }
    if (error.message.includes('PENDING_ADMIN_DECOUPLE')) {
      return res.status(400).json({ error: error.message });
    }
    if (error.message.includes('2FA')) {
      return res.status(401).json({ error: error.message });
    }
    if (error.message.includes('Invalid 2FA')) {
      return res.status(401).json({ error: error.message });
    }
    if (error.message.includes('Concurrent state transition')) {
      return res.status(409).json({ error: error.message });
    }
    if (error.status === 409) {
      return res.status(409).json({ error: error.message });
    }
    logger.error('Execute decoupling failed:', error);
    res.status(500).json({ error: 'Failed to execute decoupling' });
  }
});

// ============================================================
// POST /decoupling/initiate
// ADMIN ONLY — starts decoupling record for a device
// ============================================================
const initiateDecoupling = asyncHandler(async (req, res) => {
  const { deviceId, emiScheduleId } = req.body;
  const actorId = req.user.id;

  if (!deviceId) {
    return res.status(400).json({ error: 'deviceId is required' });
  }

  try {
    const result = await decouplingService.initiateDecoupling(deviceId, emiScheduleId, actorId);

    res.status(201).json({
      success: true,
      message: 'Decoupling process initiated',
      data: {
        decouplingId: result.id,
        deviceId,
        state: result.state,
      },
    });
  } catch (error) {
    if (error.message.includes('already decoupled')) {
      return res.status(409).json({ error: error.message });
    }
    logger.error('Initiate decoupling failed:', error);
    res.status(500).json({ error: 'Failed to initiate decoupling' });
  }
});

// ============================================================
// POST /decoupling/:deviceId/final-payment
// ADMIN ONLY — called when final EMI payment is verified
// ============================================================
const handleFinalPayment = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { paymentId, amount } = req.body;

  if (!paymentId || !amount) {
    return res.status(400).json({ error: 'paymentId and amount are required' });
  }

  try {
    const result = await decouplingService.handleFinalPayment(deviceId, paymentId, amount);

    if (!result) {
      return res.json({
        success: true,
        message: 'Payment recorded but not yet fully paid. Decoupling not triggered.',
        data: { deviceId, fullyPaid: false },
      });
    }

    res.json({
      success: true,
      message: 'Final payment verified. Decoupling process has started.',
      data: {
        deviceId,
        fullyPaid: true,
        state: result.state,
      },
    });
  } catch (error) {
    if (error.message.includes('No decoupling record')) {
      return res.status(404).json({ error: error.message });
    }
    if (error.message.includes('state')) {
      return res.status(400).json({ error: error.message });
    }
    logger.error('Handle final payment failed:', error);
    res.status(500).json({ error: 'Failed to process final payment for decoupling' });
  }
});

// ============================================================
// POST /decoupling/:deviceId/notify-dealer
// ADMIN ONLY — manually triggers dealer notification + 5-day window
// ============================================================
const notifyDealer = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  try {
    const result = await decouplingService.notifyDealer(deviceId);

    res.json({
      success: true,
      message: 'Dealer notified. 5-day fraud review window started.',
      data: {
        deviceId,
        state: result.state,
        fraudWindowEndsAt: result.fraud_window_ends_at,
      },
    });
  } catch (error) {
    if (error.message.includes('No decoupling record')) {
      return res.status(404).json({ error: error.message });
    }
    if (error.message.includes('state')) {
      return res.status(400).json({ error: error.message });
    }
    logger.error('Notify dealer failed:', error);
    res.status(500).json({ error: 'Failed to notify dealer' });
  }
});

// ============================================================
// GET /decoupling/:deviceId/padt-check
// Device calls this on network reconnect to check for pending PADT
// ============================================================
const checkPADT = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  if (req.device && req.device.id !== deviceId) {
    return res.status(403).json({ error: 'Device can only check its own PADT status' });
  }

  const result = await decouplingService.checkPADTOnReconnect(deviceId);

  if (!result) {
    return res.json({
      success: true,
      data: { pending: false, message: 'No pending PADT for this device' },
    });
  }

  res.json({
    success: true,
    data: result,
  });
});

// ============================================================
// GET /decoupling/stats
// ADMIN ONLY — decoupling statistics
// ============================================================
const getStats = asyncHandler(async (req, res) => {
  const stats = await decouplingService.getStats();

  res.json({
    success: true,
    data: { stats },
  });
});

module.exports = {
  getStatus,
  getAuditTrail,
  flagFraud,
  confirmFraud,
  rejectFraud,
  executeDecoupling,
  initiateDecoupling,
  handleFinalPayment,
  notifyDealer,
  checkPADT,
  getStats,
};
