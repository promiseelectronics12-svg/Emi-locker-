const express = require('express');
const asyncHandler = require('express-async-handler');
const db = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');

const router = express.Router();

router.use(authenticateToken);
router.use(requireRole('dealer', 'reseller', 'admin'));

router.get('/', asyncHandler(async (req, res) => {
  const params = [];
  let where = '1=1';

  if (req.user.role === 'dealer') {
    params.push(req.user.id);
    where += ` AND (
      a.dealer_id = $${params.length}
      OR d.dealer_id = $${params.length}
      OR EXISTS (
        SELECT 1 FROM dealers dl
        WHERE (dl.user_id = $${params.length} OR dl.id = $${params.length})
        AND (
          dl.user_id = a.dealer_id
          OR dl.id = a.dealer_id
          OR dl.user_id = d.dealer_id
          OR dl.id = d.dealer_id
        )
      )
    )`;
  } else if (req.user.role === 'reseller') {
    params.push(req.user.id);
    where += ` AND EXISTS (
      SELECT 1 FROM dealers dl
      WHERE dl.reseller_id = $${params.length}
      AND (
        dl.user_id = a.dealer_id
        OR dl.id = a.dealer_id
        OR dl.user_id = d.dealer_id
        OR dl.id = d.dealer_id
      )
    )`;
  }

  const result = await db.query(
    `SELECT
       a.id,
       a.dealer_id,
       a.device_id,
       a.alert_type,
       a.title,
       a.message,
       a.metadata,
       COALESCE(a.status, 'active') AS status,
       a.created_at,
       d.device_name,
       d.imei
     FROM alerts a
     LEFT JOIN devices d ON d.id = a.device_id
     WHERE ${where}
     ORDER BY a.created_at DESC
     LIMIT 100`,
    params
  );

  return res.json({ alerts: result.rows, total: result.rows.length });
}));

module.exports = router;
