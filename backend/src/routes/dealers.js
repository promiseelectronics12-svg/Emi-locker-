const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const { validateRequest } = require('../middleware/validateRequest');
const { authenticateToken } = require('../middleware/auth');
const { requireMinRole } = require('../middleware/rbac');
const { buildErrorResponse } = require('../middleware/errorHandler');
const asyncHandler = require('express-async-handler');
const db = require('../config/database');

// NID verification is deferred — will be added in a future release.
// nid column exists in the schema and remains nullable.
const validateDealer = [
  body('name').notEmpty().trim(),
  body('email').isEmail().normalizeEmail(),
  body('phone').isMobilePhone('bn-BD'),
  body('address').notEmpty(),
  body('nid').optional({ nullable: true }).isLength({ min: 10, max: 17 }),
  body('role').isIn(['dealer', 'reseller']),
  validateRequest
];

const registerDealer = asyncHandler(async (req, res) => {
  const { name, email, phone, address, nid, business_name, role } = req.body;
  const nidValue = nid || null;

  // Duplicate check: always check email + phone; only add NID check when provided
  let existing;
  if (nidValue) {
    existing = await db.query(
      'SELECT id FROM dealers WHERE email = $1 OR phone = $2 OR nid = $3',
      [email, phone, nidValue]
    );
  } else {
    existing = await db.query(
      'SELECT id FROM dealers WHERE email = $1 OR phone = $2',
      [email, phone]
    );
  }

  if (existing.rows.length > 0) {
    return res.status(409).json(buildErrorResponse(409, 'CONFLICT', 'Dealer already exists'));
  }

  const result = await db.query(
    `INSERT INTO dealers (name, email, phone, address, nid, business_name, role, status, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'active', NOW())
     RETURNING id, name, email, role, status`,
    [name, email, phone, address, nidValue, business_name, role]
  );

  res.status(201).json(result.rows[0]);
});

const getDealer = asyncHandler(async (req, res) => {
  const result = await db.query(
    'SELECT * FROM dealers WHERE id = $1',
    [req.params.id]
  );
  
  if (result.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer not found'));
  }
  
  res.json(result.rows[0]);
});

const getMyDealerProfile = asyncHandler(async (req, res) => {
  const result = await db.query(
    'SELECT * FROM dealers WHERE user_id = $1',
    [req.user.id]
  );
  
  if (result.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer profile not found'));
  }
  
  res.json(result.rows[0]);
});

const updateDealer = asyncHandler(async (req, res) => {
  const { name, phone, address, business_name } = req.body;
  
  const result = await db.query(
    `UPDATE dealers SET name = $1, phone = $2, address = $3, business_name = $4, updated_at = NOW()
     WHERE id = $5
     RETURNING *`,
    [name, phone, address, business_name, req.params.id]
  );
  
  if (result.rows.length === 0) {
    return res.status(404).json(buildErrorResponse(404, 'DEALER_NOT_FOUND', 'Dealer not found'));
  }
  
  res.json(result.rows[0]);
});

const getDealerDevices = asyncHandler(async (req, res) => {
  const result = await db.query(
    `SELECT d.*, u.name as owner_name, u.phone as owner_phone
     FROM devices d
     LEFT JOIN users u ON d.owner_id = u.id
     WHERE d.dealer_id = $1
     ORDER BY d.created_at DESC`,
    [req.params.id]
  );
  
  res.json(result.rows);
});

router.post('/', authenticateToken, requireMinRole('reseller'), validateDealer, registerDealer);
router.get('/me', authenticateToken, getMyDealerProfile);
router.get('/:id', authenticateToken, getDealer);
router.patch('/:id', authenticateToken, updateDealer);
router.get('/:id/devices', authenticateToken, getDealerDevices);

module.exports = router;
