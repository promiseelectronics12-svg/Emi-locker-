const express = require('express');
const jwt = require('jsonwebtoken');
const db = require('../../config/database');
const { formatSchedule } = require('../enrollment/enrollmentService');
const logger = require('../../utils/logger');

const router = express.Router();

async function validateDeviceToken(req, res, next) {
  const token = req.headers['x-device-token'];
  if (!token) return res.status(401).json({ success: false, error: 'Device token required' });

  try {
    const secret = process.env.DEVICE_TOKEN_SECRET || process.env.JWT_SECRET;
    if (!secret) return res.status(500).json({ success: false, error: 'Server misconfigured' });

    const payload = jwt.verify(token, secret);
    if (payload.type !== 'device' || !payload.sub) {
      return res.status(401).json({ success: false, error: 'Invalid device token' });
    }

    req.deviceAuth = payload;
    next();
  } catch (error) {
    logger.warn('Device token validation failed', { error: error.message });
    return res.status(401).json({ success: false, error: 'Invalid device token' });
  }
}

async function loadSchedule(deviceId) {
  const scheduleResult = await db.query(
    `SELECT *
     FROM emi_schedules
     WHERE device_id = $1 AND status = 'active'
     ORDER BY created_at DESC
     LIMIT 1`,
    [deviceId]
  );

  const schedule = scheduleResult.rows[0];
  if (!schedule) return null;

  const paymentsResult = await db.query(
    `SELECT installment_number, payment_status, status
     FROM emi_payments
     WHERE emi_schedule_id = $1
       AND COALESCE(payment_status, status) IN ('completed', 'paid', 'success')
     ORDER BY installment_number`,
    [schedule.id]
  );

  const paid = new Set(paymentsResult.rows.map(row => Number(row.installment_number)).filter(Boolean));
  const formatted = formatSchedule(schedule);
  formatted.installments = formatted.installments.map(installment => ({
    ...installment,
    status: paid.has(installment.installmentNumber) ? 'PAID' : 'PENDING'
  }));
  return formatted;
}

router.get('/emi-schedule', validateDeviceToken, async (req, res) => {
  try {
    const schedule = await loadSchedule(req.deviceAuth.sub);
    return res.json({ success: true, emi_schedule: schedule });
  } catch (error) {
    logger.error('Device schedule refresh failed', { error: error.message });
    return res.status(500).json({ success: false, error: 'Failed to load EMI schedule' });
  }
});

module.exports = router;
