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
  // Available counts come from reseller quota columns (on-demand model).
  // Assigned/activated counts come from key rows already generated.
  const [quotaRes, keyRes] = await Promise.all([
    db.query(
      `SELECT COALESCE(quota_standard, 0) AS standard_available,
              COALESCE(quota_premium,  0) AS premium_available
       FROM resellers WHERE id = $1`,
      [resellerId]
    ),
    db.query(
      `SELECT
         COUNT(*)::int                                                              AS available_keys,
         COUNT(*) FILTER (WHERE status = 'assigned')::int                          AS assigned_keys,
         COUNT(*) FILTER (WHERE status = 'activated')::int                         AS activated_keys,
         COUNT(*) FILTER (WHERE status = 'assigned' AND tier = 'standard')::int    AS standard_assigned,
         COUNT(*) FILTER (WHERE status = 'assigned' AND tier = 'premium')::int     AS premium_assigned
       FROM activation_keys
       WHERE reseller_id = $1`,
      [resellerId]
    ),
  ]);
  const keys = { rows: [{ ...quotaRes.rows[0], ...keyRes.rows[0] }] };
  // available_keys = sum of per-tier quota
  keys.rows[0].available_keys =
    (keys.rows[0].standard_available || 0) +
    (keys.rows[0].premium_available  || 0);
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

router.post('/dealers', asyncHandler(async (req, res) => {
  const { name, email, phone, shopName, businessName, address, district, division, thana, tradeLicense, nid, photoUrl, password } = req.body;
  const resellerId = req.user.id;

  if (!name || !email || !phone || !password) {
    return res.status(400).json({ error: 'Name, email, phone and password are required' });
  }

  const bcrypt = require('bcryptjs');
  const { getClient } = db;
  const client = await getClient();
  try {
    await client.query('BEGIN');

    const existing = await client.query(
      'SELECT id FROM users WHERE email = $1 OR phone = $2',
      [email.toLowerCase().trim(), phone.trim()]
    );
    if (existing.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({ error: 'Email or phone already registered' });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const userResult = await client.query(
      `INSERT INTO users (email, password_hash, name, phone, role, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, 'dealer', 'active', NOW(), NOW())
       RETURNING id`,
      [email.toLowerCase().trim(), passwordHash, name.trim(), phone.trim()]
    );
    const userId = userResult.rows[0].id;

    await client.query(
      `INSERT INTO dealers
         (user_id, reseller_id, name, email, phone, shop_name, business_name,
          address, district, division, thana, trade_license, nid, photo_url,
          status, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,'active',NOW(),NOW())`,
      [userId, resellerId, name.trim(), email.toLowerCase().trim(), phone.trim(),
       shopName || null, businessName || null, address || null, district || null,
       division || null, thana || null, tradeLicense || null, nid || null, photoUrl || null]
    );

    await client.query('COMMIT');
    return res.status(201).json({ success: true, message: 'Dealer created' });
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
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

// Credit score network — regional aggregate view (no individual customer data)
router.get('/credit/summary', asyncHandler(async (req, res) => {
  const resellerId = req.user.id;

  // Score tier distribution across all dealers under this reseller
  const tierDist = await db.query(
    `SELECT ccp.tier, COUNT(*) as count
     FROM customer_credit_profiles ccp
     JOIN profile_seed_index psi ON psi.nid_hash = ccp.nid_hash
     JOIN users u ON u.id = psi.seed_holder_id
     JOIN dealers d ON d.user_id = u.id
     WHERE d.reseller_id = $1
       AND psi.seed_type = 'DEALER_DRIVE'
     GROUP BY ccp.tier
     ORDER BY ccp.tier`,
    [resellerId]
  );

  const blacklistCount = await db.query(
    `SELECT COUNT(*) as total FROM fraud_blacklist
     WHERE active = TRUE
       AND nid_hash IN (
         SELECT psi.nid_hash FROM profile_seed_index psi
         JOIN users u ON u.id = psi.seed_holder_id
         JOIN dealers d ON d.user_id = u.id
         WHERE d.reseller_id = $1
       )`,
    [resellerId]
  );

  res.json({
    tier_distribution: tierDist.rows,
    active_blacklist_count: parseInt(blacklistCount.rows[0].total, 10),
    generated_at: new Date().toISOString(),
  });
}));

// Register that this reseller holds a customer profile backup in their Google Drive
router.post('/profiles/register-seed', asyncHandler(async (req, res) => {
  const { nid_hash } = req.body;

  if (!nid_hash || nid_hash.length !== 64) {
    return res.status(400).json({ success: false, error: 'Valid SHA-256 nid_hash required' });
  }

  await db.query(
    `INSERT INTO profile_seed_index (nid_hash, seed_type, seed_holder_id, last_synced_at)
     VALUES ($1, 'RESELLER_DRIVE', $2, NOW())
     ON CONFLICT (nid_hash, seed_type, seed_holder_id) DO UPDATE SET last_synced_at = NOW()`,
    [nid_hash, req.user.id]
  );

  res.json({ success: true });
}));

router.get('/quota', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT COALESCE(monthly_key_quota, monthly_quota, 100) AS monthly_quota,
            COALESCE(used_keys, 0)     AS used_keys,
            COALESCE(quota_standard, 0) AS quota_standard,
            COALESCE(quota_premium,  0) AS quota_premium
     FROM resellers
     WHERE id = $1`,
    [req.user.id]
  );
  if (result.rows.length === 0) return res.status(404).json({ error: 'Reseller not found' });
  return res.json(result.rows[0]);
}));

// ── Credit ledger ────────────────────────────────────────────────────────────

router.get('/credit', asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT dcl.id, dcl.dealer_id, d.name AS dealer_name, d.phone AS dealer_phone,
            dcl.keys_quantity, dcl.tier, dcl.notes, dcl.due_date,
            dcl.settled_at, dcl.status, dcl.created_at
     FROM dealer_credit_ledger dcl
     LEFT JOIN dealers d ON d.id = dcl.dealer_id OR d.user_id = dcl.dealer_id
     WHERE dcl.reseller_id = $1
     ORDER BY dcl.status ASC, dcl.created_at DESC`,
    [req.user.id]
  );
  return res.json({ entries: result.rows, total: result.rows.length });
}));

router.patch('/credit/:id/settle', asyncHandler(async (req, res) => {
  const result = await db.query(
    `UPDATE dealer_credit_ledger
     SET status = 'settled', settled_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND reseller_id = $2 AND status = 'pending'
     RETURNING *`,
    [req.params.id, req.user.id]
  );
  if (result.rows.length === 0) {
    return res.status(404).json({ error: 'Entry not found or already settled' });
  }
  return res.json({ success: true, entry: result.rows[0] });
}));

module.exports = router;
