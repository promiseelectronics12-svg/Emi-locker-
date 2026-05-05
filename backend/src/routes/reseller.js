const express = require('express');
const asyncHandler = require('express-async-handler');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const keyController = require('../modules/keys/keyController');

const router = express.Router();

router.use(authenticateToken);
router.use(requireRole('reseller'));

router.get('/stats', asyncHandler(async (req, res) => {
  const resellerId = req.user.id;

  const dealers = await db.query(
    'SELECT COUNT(*)::int as total_dealers FROM dealers WHERE reseller_id = $1',
    [resellerId]
  );
  const keys = await db.query(
    `SELECT
       COUNT(*) FILTER (WHERE status = 'available')::int as available_keys,
       COUNT(*) FILTER (WHERE status = 'assigned')::int as assigned_keys,
       COUNT(*) FILTER (WHERE status = 'activated')::int as activated_keys
     FROM activation_keys
     WHERE reseller_id = $1`,
    [resellerId]
  );
  const requests = await db.query(
    `SELECT COUNT(*) FILTER (WHERE status = 'pending')::int as pending_requests
     FROM key_requests
     WHERE reseller_id = $1`,
    [resellerId]
  );

  return res.json({
    ...dealers.rows[0],
    ...keys.rows[0],
    ...requests.rows[0]
  });
}));

router.get('/dealers', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT id, user_id, name, email, phone, address, business_name, shop_name, status, created_at
     FROM dealers
     WHERE reseller_id = $1
     ORDER BY created_at DESC`,
    [req.user.id]
  );
  return res.json({ dealers: result.rows, total: result.rows.length });
}));

router.get('/dealers/applications', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT id, user_id, name, email, phone, address, business_name, shop_name, status, created_at
     FROM dealers
     WHERE reseller_id = $1 AND status IN ('pending', 'applied')
     ORDER BY created_at DESC`,
    [req.user.id]
  );
  return res.json({ applications: result.rows, total: result.rows.length });
}));

router.get('/dealers/applications/:id', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT * FROM dealers
     WHERE id = $1 AND reseller_id = $2`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer application not found' });
  return res.json(result.rows[0]);
}));

router.post('/dealers/applications/:id/approve', asyncHandler(async (req, res) => {
  const result = await db.query(
    `UPDATE dealers
     SET status = 'active', updated_at = NOW()
     WHERE id = $1 AND reseller_id = $2
     RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer application not found' });
  return res.json(result.rows[0]);
}));

router.post('/dealers/applications/:id/reject', asyncHandler(async (req, res) => {
  const result = await db.query(
    `UPDATE dealers
     SET status = 'rejected', updated_at = NOW()
     WHERE id = $1 AND reseller_id = $2
     RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer application not found' });
  return res.json(result.rows[0]);
}));

router.get('/dealers/:id', asyncHandler(async (req, res) => {
  const result = await db.query(
    'SELECT * FROM dealers WHERE id = $1 AND reseller_id = $2',
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer not found' });
  return res.json(result.rows[0]);
}));

router.get('/dealers/:id/performance', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT
       COUNT(d.id)::int as total_devices,
       COUNT(ak.id) FILTER (WHERE ak.status = 'activated')::int as activated_keys
     FROM dealers dl
     LEFT JOIN devices d ON d.dealer_id = dl.id OR d.dealer_id = dl.user_id
     LEFT JOIN activation_keys ak ON ak.dealer_id = dl.id OR ak.dealer_id = dl.user_id
     WHERE dl.id = $1 AND dl.reseller_id = $2`,
    [req.params.id, req.user.id]
  );
  return res.json(result.rows[0] || {});
}));

router.post('/dealers/:id/suspend', asyncHandler(async (req, res) => {
  const result = await db.query(
    `UPDATE dealers SET status = 'suspended', suspended_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND reseller_id = $2 RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer not found' });
  return res.json(result.rows[0]);
}));

router.post('/dealers/:id/reactivate', asyncHandler(async (req, res) => {
  const result = await db.query(
    `UPDATE dealers SET status = 'active', reactivated_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND reseller_id = $2 RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Dealer not found' });
  return res.json(result.rows[0]);
}));

router.post('/dealers/:dealerId/assign-keys', (req, res, next) => {
  req.body.dealerId = req.params.dealerId;
  return keyController.assignKeys(req, res, next);
});

router.post('/keys/request', keyController.requestKeys);
router.get('/keys/requests', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT * FROM key_requests
     WHERE reseller_id = $1
     ORDER BY created_at DESC`,
    [req.user.id]
  );
  return res.json({ requests: result.rows, total: result.rows.length });
}));

router.get('/keys/requests/:id', asyncHandler(async (req, res) => {
  const result = await db.query(
    'SELECT * FROM key_requests WHERE id = $1 AND reseller_id = $2',
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Key request not found' });
  return res.json(result.rows[0]);
}));

router.get('/keys/inventory', keyController.getResellerKeys);

router.get('/quota', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT COALESCE(monthly_key_quota, monthly_quota, 100) as monthly_quota,
            COALESCE(used_keys, 0) as used_keys
     FROM resellers
     WHERE id = $1`,
    [req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Reseller not found' });
  return res.json(result.rows[0]);
}));

module.exports = router;
