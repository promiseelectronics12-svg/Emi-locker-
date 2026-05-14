const asyncHandler = require('express-async-handler');
const emiService = require('./emiService');
const emiModel = require('./emiModel');
const {
  validateRequest,
  scheduleValidation,
  deviceIdParam,
  paymentValidation,
  gracePeriodValidation,
  upcomingQueryValidation
} = require('./emiValidation');
const logger = require('../../utils/logger');

const createSchedule = asyncHandler(async (req, res) => {
  const { deviceId, totalAmount, downPayment, emiAmount, duration, startDate, graceDays } =
    req.body;
  const dealerId = req.user?.id || req.body.dealerId;

  if (!dealerId) {
    return res.status(401).json({ error: 'Dealer ID is required' });
  }

  const validation = await emiService.validateScheduleAmounts(
    totalAmount,
    downPayment,
    emiAmount,
    duration
  );

  if (!validation.valid) {
    return res.status(400).json({
      error: 'Invalid EMI schedule amounts',
      details: validation.errors
    });
  }

  try {
    const schedule = await emiService.createSchedule({
      deviceId,
      totalAmount,
      downPayment,
      emiAmount,
      duration,
      startDate,
      graceDays: graceDays || 7,
      dealerId
    });

    logger.info(`EMI schedule created for device ${deviceId}`, {
      scheduleId: schedule.id,
      dealerId,
      totalAmount,
      duration
    });

    res.status(201).json({
      success: true,
      message: 'EMI schedule created successfully',
      data: {
        scheduleId: schedule.id,
        deviceId,
        totalAmount,
        downPayment,
        emiAmount,
        duration,
        startDate,
        graceDays: graceDays || 7,
        status: schedule.status
      }
    });
  } catch (error) {
    logger.error('Failed to create EMI schedule:', error);

    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (error.message.includes('already exists')) {
      return res.status(409).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to create EMI schedule' });
  }
});

const getSchedule = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  try {
    const schedule = await emiService.getScheduleWithPayments(deviceId);

    if (!schedule) {
      return res.status(404).json({ error: 'No EMI schedule found for this device' });
    }

    const decouplingStatus = await emiService.getDecouplingStatus(deviceId);

    res.json({
      success: true,
      data: {
        schedule: {
          id: schedule.id,
          deviceId: schedule.device_id,
          totalAmount: parseFloat(schedule.total_amount),
          downPayment: parseFloat(schedule.down_payment),
          emiAmount: parseFloat(schedule.emi_amount),
          duration: schedule.duration,
          startDate: schedule.start_date,
          graceDays: schedule.grace_days,
          status: schedule.status,
          createdAt: schedule.created_at
        },
        device: {
          deviceName: schedule.device_name,
          imei: schedule.imei,
          model: schedule.model,
          brand: schedule.brand,
          ownerId: schedule.owner_id
        },
        dealer: {
          name: schedule.dealer_name,
          phone: schedule.dealer_phone,
          email: schedule.dealer_email
        },
        installments: schedule.installments,
        payments: schedule.payments,
        summary: schedule.summary,
        overdueStatus: schedule.overdueStatus,
        decoupling: decouplingStatus
      }
    });
  } catch (error) {
    logger.error('Failed to get EMI schedule:', error);

    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    res.status(500).json({ error: 'Failed to retrieve EMI schedule' });
  }
});

const recordPayment = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { amount, method, txId, installmentNumber, note } = req.body;
  const recordedBy = req.user?.id || 'system';

  if (!amount || parseFloat(amount) <= 0) {
    return res.status(400).json({ error: 'Valid payment amount is required' });
  }

  if (!method) {
    return res.status(400).json({ error: 'Payment method is required' });
  }

  try {
    const payment = await emiService.recordPayment(deviceId, {
      amount,
      method,
      txId,
      installmentNumber,
      note,
      recordedBy
    });

    logger.info(`Payment recorded for device ${deviceId}`, {
      paymentId: payment.id,
      amount,
      method,
      deviceId,
      isFinalPayment: payment.isFinalPayment
    });

    res.status(201).json({
      success: true,
      message: payment.isFinalPayment
        ? 'Final payment recorded! Decoupling process initiated.'
        : 'Payment recorded successfully',
      data: {
        paymentId: payment.id,
        deviceId,
        amount: parseFloat(payment.amount),
        method: payment.method,
        txId: payment.tx_id,
        installmentNumber: payment.installment_number,
        status: payment.status,
        totalPaid: payment.total_paid,
        remaining: payment.remaining,
        isFinalPayment: payment.isFinalPayment
      }
    });
  } catch (error) {
    logger.error('Failed to record payment:', error);

    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (error.message.includes('No EMI schedule')) {
      return res.status(404).json({ error: error.message });
    }

    if (error.message.includes('not active')) {
      return res.status(400).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to record payment' });
  }
});

const getOverdueStatus = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  try {
    const overdueStatus = await emiService.getOverdueStatus(deviceId);
    const lockRecommendation = await emiService.getLockRecommendation(deviceId);

    res.json({
      success: true,
      data: {
        deviceId: overdueStatus.deviceId,
        scheduleId: overdueStatus.scheduleId,
        isOverdue: overdueStatus.isOverdue,
        daysOverdue: overdueStatus.daysOverdue,
        currentInstallment: overdueStatus.currentInstallment,
        lockRecommendation,
        message: overdueStatus.isOverdue
          ? `Payment is ${overdueStatus.daysOverdue} days overdue`
          : 'Payment is current'
      }
    });
  } catch (error) {
    logger.error('Failed to get overdue status:', error);

    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    res.status(500).json({ error: 'Failed to retrieve overdue status' });
  }
});

const requestGracePeriod = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { reason } = req.body;
  const requestedBy = req.user?.id || 'dealer';

  try {
    const gracePeriod = await emiService.requestGracePeriod(deviceId, reason, requestedBy);

    logger.info(`Grace period requested for device ${deviceId}`, {
      gracePeriodId: gracePeriod.id,
      reason,
      requestedBy
    });

    res.status(201).json({
      success: true,
      message: 'Grace period of 14 days has been granted',
      data: {
        gracePeriodId: gracePeriod.id,
        deviceId,
        daysAdded: 14,
        reason,
        status: gracePeriod.status,
        validUntil: gracePeriod.created_at
          ? new Date(
              new Date(gracePeriod.created_at).getTime() + 14 * 24 * 60 * 60 * 1000
            ).toISOString()
          : null
      }
    });
  } catch (error) {
    logger.error('Failed to request grace period:', error);

    if (error.message.includes('No active EMI schedule')) {
      return res.status(404).json({ error: error.message });
    }

    if (error.message.includes('Maximum grace period')) {
      return res.status(429).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to request grace period' });
  }
});

const getUpcoming = asyncHandler(async (req, res) => {
  const days = parseInt(req.query.days, 10) || 7;

  try {
    const upcomingDevices = await emiService.getUpcomingDueDevices(days);

    const formattedDevices = upcomingDevices.map((device) => {
      const nextDueDate = device.next_due_date ? new Date(device.next_due_date) : null;
      const daysUntilDue = nextDueDate
        ? Math.ceil((nextDueDate - new Date()) / (1000 * 60 * 60 * 24))
        : null;

      return {
        deviceId: device.device_id,
        deviceName: device.device_name,
        imei: device.imei,
        model: device.model,
        brand: device.brand,
        emiAmount: parseFloat(device.emi_amount),
        scheduleId: device.schedule_id,
        nextDueDate,
        daysUntilDue,
        graceDays: device.grace_days,
        dealer: {
          name: device.dealer_name,
          phone: device.dealer_phone,
          email: device.dealer_email
        }
      };
    });

    res.json({
      success: true,
      data: {
        devices: formattedDevices,
        count: formattedDevices.length,
        daysLookAhead: days
      }
    });
  } catch (error) {
    logger.error('Failed to get upcoming due devices:', error);
    res.status(500).json({ error: 'Failed to retrieve upcoming devices' });
  }
});

const getDecouplingStatus = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  try {
    const status = await emiService.getDecouplingStatus(deviceId);

    if (!status) {
      return res.status(404).json({ error: 'No decoupling process found for this device' });
    }

    res.json({
      success: true,
      data: status
    });
  } catch (error) {
    logger.error('Failed to get decoupling status:', error);
    res.status(500).json({ error: 'Failed to retrieve decoupling status' });
  }
});

const flagFraud = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { reason } = req.body;
  const flaggedBy = req.user?.id || req.body.flaggedBy;

  if (!flaggedBy) {
    return res.status(401).json({ error: 'Authentication required to flag fraud' });
  }

  try {
    const result = await emiService.flagFraud(deviceId, flaggedBy, reason);

    logger.warn(`Fraud flagged for device ${deviceId}`, { flaggedBy, reason });

    res.json({
      success: true,
      message: 'Fraud flag has been raised. Admin review will be triggered.',
      data: {
        deviceId,
        fraudFlagged: result.fraud_flag,
        flaggedAt: result.fraud_flagged_at,
        fraudReason: result.fraud_reason
      }
    });
  } catch (error) {
    logger.error('Failed to flag fraud:', error);

    if (
      error.message.includes('Cannot flag fraud') ||
      error.message.includes('window has expired')
    ) {
      return res.status(400).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to flag fraud' });
  }
});

const executeDecoupling = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;
  const { rtocCode } = req.body;
  const executedBy = req.user?.id;

  if (!executedBy) {
    return res.status(401).json({ error: 'Admin authentication required to execute decoupling' });
  }

  if (!rtocCode) {
    return res.status(400).json({ error: 'RTOC code is required' });
  }

  try {
    const result = await emiService.executeDecoupling(deviceId, rtocCode, executedBy);

    logger.info(`Decoupling executed for device ${deviceId}`, {
      executedBy,
      rtocCode
    });

    res.json({
      success: true,
      message: 'Device has been successfully decoupled. All restrictions have been lifted.',
      data: {
        deviceId,
        rtocCode: result.rtocCode,
        decoupledAt: result.decoupledAt
      }
    });
  } catch (error) {
    logger.error('Failed to execute decoupling:', error);

    if (error.message.includes('Invalid RTOC')) {
      return res.status(400).json({ error: 'Invalid RTOC code' });
    }

    if (error.message.includes('not in a state')) {
      return res.status(400).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to execute decoupling' });
  }
});

const getLockStatus = asyncHandler(async (req, res) => {
  const { deviceId } = req.params;

  try {
    const overdueStatus = await emiService.getOverdueStatus(deviceId);
    const lockRecommendation = await emiService.getLockRecommendation(deviceId);

    res.json({
      success: true,
      data: {
        deviceId,
        isOverdue: overdueStatus.isOverdue,
        daysOverdue: overdueStatus.daysOverdue,
        currentInstallment: overdueStatus.currentInstallment,
        recommendedAction: lockRecommendation.action,
        lockLevel: lockRecommendation.lockLevel,
        reason: lockRecommendation.reason,
        message: lockRecommendation.message
      }
    });
  } catch (error) {
    logger.error('Failed to get lock status:', error);
    res.status(500).json({ error: 'Failed to retrieve lock status' });
  }
});

module.exports = {
  createSchedule,
  getSchedule,
  recordPayment,
  getOverdueStatus,
  requestGracePeriod,
  getUpcoming,
  getDecouplingStatus,
  flagFraud,
  executeDecoupling,
  getLockStatus,
  validateRequest,
  scheduleValidation,
  deviceIdParam,
  paymentValidation,
  gracePeriodValidation,
  upcomingQueryValidation
};
