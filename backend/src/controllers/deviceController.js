const { body, param, query } = require('express-validator');
const asyncHandler = require('express-async-handler');
const { validateRequest } = require('../middleware/validateRequest');
const { authenticateToken } = require('../middleware/auth');
const db = require('../config/database');
const logger = require('../utils/logger');

const validateDeviceOwnership = asyncHandler(async (req, res, next) => {
  const device = await db.query('SELECT owner_id FROM devices WHERE id = $1', [req.params.id]);

  if (device.rows.length === 0) {
    return res.status(404).json({ error: 'Device not found' });
  }

  if (device.rows[0].owner_id !== req.user.id) {
    return res.status(403).json({ error: 'Access denied' });
  }

  next();
});

const registerDevice = asyncHandler(async (req, res) => {
  const { imei, enrollment_token, dealer_id } = req.body;

  if (!imei || !enrollment_token || !dealer_id) {
    return res.status(400).json({ error: 'IMEI, enrollment token, and dealer ID are required' });
  }

  if (!/^\d{15}$/.test(imei)) {
    return res.status(400).json({ error: 'Invalid IMEI format' });
  }

  const existing = await db.query('SELECT id FROM devices WHERE imei = $1', [imei]);

  if (existing.rows.length > 0) {
    return res.status(409).json({ error: 'Device already registered' });
  }

  const result = await db.query(
    `INSERT INTO devices (imei, enrollment_token, dealer_id, status, created_at)
     VALUES ($1, $2, $3, 'pending', NOW())
     RETURNING id, imei, status`,
    [imei, enrollment_token, dealer_id]
  );

  logger.info(`Device registered: ${imei}`);
  res.status(201).json(result.rows[0]);
});

const getDevice = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT d.*, u.name as owner_name, u.phone as owner_phone
     FROM devices d
     LEFT JOIN users u ON d.owner_id = u.id
     WHERE d.id = $1`,
    [req.params.id]
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Device not found' });
  }

  res.json(result.rows[0]);
});

const getMyDevices = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT id, imei, model, brand, status, monthly_amount, emi_remaining, created_at
     FROM devices WHERE owner_id = $1 ORDER BY created_at DESC`,
    [req.user.id]
  );

  res.json(result.rows);
});

const updateDeviceStatus = asyncHandler(async (req, res) => {
  const { status, reason } = req.body;

  const validStatuses = ['active', 'locked', 'unlocked', 'stolen', 'disabled'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }

  const result = await db.query(
    `UPDATE devices SET status = $1, updated_at = NOW()
     WHERE id = $2 AND (owner_id = $3 OR $3 = ANY(SELECT role FROM users WHERE id = $3))
     RETURNING *`,
    [status, req.params.id, req.user.id]
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Device not found or access denied' });
  }

  logger.info(`Device ${req.params.id} status changed to ${status}: ${reason}`);
  res.json(result.rows[0]);
});

const lockDevice = asyncHandler(async (req, res) => {
  const { reason } = req.body;

  const result = await db.query(
    `UPDATE devices SET status = 'locked', updated_at = NOW()
     WHERE id = $1 AND owner_id = $2
     RETURNING *`,
    [req.params.id, req.user.id]
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Device not found or not owned by you' });
  }

  logger.warn(`Device ${req.params.id} locked: ${reason}`);
  res.json({ message: 'Device locked successfully', device: result.rows[0] });
});

const unlockDevice = asyncHandler(async (req, res) => {
  const { reason } = req.body;

  const result = await db.query(
    `UPDATE devices SET status = 'active', updated_at = NOW()
     WHERE id = $1 AND owner_id = $2 AND status = 'locked'
     RETURNING *`,
    [req.params.id, req.user.id]
  );

  if (result.rows.length === 0) {
    return res.status(400).json({ error: 'Device not found, not locked, or not owned by you' });
  }

  logger.info(`Device ${req.params.id} unlocked: ${reason}`);
  res.json({ message: 'Device unlocked successfully', device: result.rows[0] });
});

module.exports = {
  registerDevice,
  getDevice,
  getMyDevices,
  updateDeviceStatus,
  lockDevice,
  unlockDevice,
  validateDeviceOwnership
};
