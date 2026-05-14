const express = require('express');

const router = express.Router();
const asyncHandler = require('express-async-handler');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const db = require('../config/database');

const getAllUsers = asyncHandler(async (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const limit = parseInt(req.query.limit, 10) || 50;
  const offset = (page - 1) * limit;

  const result = await db.query(
    `SELECT id, email, name, phone, role, status, created_at, last_login
     FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
    [limit, offset]
  );

  const countResult = await db.query('SELECT COUNT(*) FROM users');

  res.json({
    users: result.rows,
    total: parseInt(countResult.rows[0].count, 10),
    page,
    limit,
    pages: Math.ceil(parseInt(countResult.rows[0].count, 10) / limit)
  });
});

const getAllDealers = asyncHandler(async (req, res) => {
  const result = await db.query('SELECT * FROM dealers ORDER BY created_at DESC');
  res.json(result.rows);
});

const getAllDevices = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT d.*, u.name as owner_name, u.phone as owner_phone, dl.name as dealer_name
     FROM devices d
     LEFT JOIN users u ON d.owner_id = u.id
     LEFT JOIN dealers dl ON d.dealer_id = dl.id
     ORDER BY d.created_at DESC`
  );
  res.json(result.rows);
});

const getAllPayments = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT p.*, u.name as user_name, u.email as user_email, d.imei, d.model
     FROM payments p
     JOIN users u ON p.user_id = u.id
     JOIN devices d ON p.device_id = d.id
     ORDER BY p.created_at DESC`
  );
  res.json(result.rows);
});

const updateUserStatus = asyncHandler(async (req, res) => {
  const { status } = req.body;

  if (!['active', 'suspended', 'disabled'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }

  const result = await db.query(
    'UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
    [status, req.params.userId]
  );

  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'User not found' });
  }

  res.json(result.rows[0]);
});

const getDashboardStats = asyncHandler(async (req, res) => {
  const stats = await db.query(`
    SELECT
      (SELECT COUNT(*) FROM users) as total_users,
      (SELECT COUNT(*) FROM dealers) as total_dealers,
      (SELECT COUNT(*) FROM devices) as total_devices,
      (SELECT COUNT(*) FROM devices WHERE status = 'active') as active_devices,
      (SELECT COUNT(*) FROM devices WHERE status = 'locked') as locked_devices,
      (SELECT COUNT(*) FROM payments WHERE status = 'confirmed' AND created_at > NOW() - INTERVAL '30 days') as monthly_payments,
      (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE status = 'confirmed' AND created_at > NOW() - INTERVAL '30 days') as monthly_revenue
  `);

  res.json(stats.rows[0]);
});

router.use(authenticateToken);
router.use(requireRole('admin'));

router.get('/users', getAllUsers);
router.patch('/users/:userId/status', updateUserStatus);
router.get('/dealers', getAllDealers);
router.get('/devices', getAllDevices);
router.get('/payments', getAllPayments);
router.get('/stats', getDashboardStats);

module.exports = router;
