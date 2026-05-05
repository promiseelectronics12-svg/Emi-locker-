const express = require('express');
const asyncHandler = require('express-async-handler');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');

const router = express.Router();

router.use(authenticateToken);
router.use(requireRole('dealer'));

async function getDealerProfile(userId) {
  const result = await db.query(
    'SELECT * FROM dealers WHERE user_id = $1 OR id = $1 LIMIT 1',
    [userId]
  );
  return result.rows[0] || null;
}

router.get('/stats', asyncHandler(async (req, res) => {
  const dealer = await getDealerProfile(req.user.id);
  const dealerIds = [req.user.id];
  if (dealer?.id) dealerIds.push(dealer.id);

  const stats = await db.query(
    `SELECT
       COUNT(*)::int as total_devices,
       COUNT(*) FILTER (WHERE status = 'locked')::int as locked_devices,
       COUNT(*) FILTER (WHERE status = 'enrolled')::int as enrolled_devices,
       COUNT(*) FILTER (WHERE status = 'decoupled')::int as decoupled_devices
     FROM devices
     WHERE dealer_id = ANY($1::uuid[])`,
    [dealerIds]
  );

  const keys = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'assigned')::int as assigned_keys,
       COUNT(*) FILTER (WHERE status = 'activated')::int as activated_keys
     FROM activation_keys
     WHERE dealer_id = ANY($1::uuid[])`,
    [dealerIds]
  );

  return res.json({
    ...stats.rows[0],
    ...keys.rows[0]
  });
}));

router.get('/analytics', asyncHandler(async (req, res) => {
  const dealer = await getDealerProfile(req.user.id);
  const dealerIds = [req.user.id];
  if (dealer?.id) dealerIds.push(dealer.id);

  const result = await db.query(
    `SELECT
       date_trunc('day', created_at)::date as day,
       COUNT(*)::int as devices_enrolled
     FROM devices
     WHERE dealer_id = ANY($1::uuid[])
       AND created_at > NOW() - INTERVAL '30 days'
     GROUP BY day
     ORDER BY day`,
    [dealerIds]
  );

  return res.json({ series: result.rows });
}));

router.get('/devices', asyncHandler(async (req, res) => {
  const dealer = await getDealerProfile(req.user.id);
  const dealerIds = [req.user.id];
  if (dealer?.id) dealerIds.push(dealer.id);

  const result = await db.query(
    `SELECT * FROM devices
     WHERE dealer_id = ANY($1::uuid[])
     ORDER BY created_at DESC`,
    [dealerIds]
  );

  return res.json({ devices: result.rows, total: result.rows.length });
}));

module.exports = router;
