const express = require('express');
const router = express.Router();
const asyncHandler = require('express-async-handler');
const { body, query } = require('express-validator');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');
const { validateRequest } = require('../../middleware/validation');
const creditScoreService = require('./creditScoreService');
const db = require('../../config/database');
const logger = require('../../utils/logger');

// Admin: manual score adjustment
router.post(
  '/admin/adjust',
  authenticateToken,
  requireRole('admin'),
  body('nid_hash').isString().isLength({ min: 64, max: 64 }).withMessage('Valid SHA-256 nid_hash required'),
  body('delta').isInt({ min: -1000, max: 1000 }).withMessage('Delta must be between -1000 and 1000'),
  body('reason').isString().isLength({ min: 1, max: 500 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash, delta, reason } = req.body;
    const result = await creditScoreService.recordPaymentEvent(nid_hash, 'MANUAL_ADJUSTMENT', delta);
    logger.info(`Manual credit adjustment by admin ${req.user.id}: nid_hash=${nid_hash} delta=${delta}`);
    res.json({ success: true, ...result, reason });
  })
);

// Admin: add to fraud blacklist
router.post(
  '/admin/blacklist',
  authenticateToken,
  requireRole('admin'),
  body('nid_hash').isString().isLength({ min: 64, max: 64 }),
  body('reason').isString().isLength({ min: 1, max: 1000 }),
  body('evidence_ref').optional().isString().isLength({ max: 255 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash, reason, evidence_ref } = req.body;

    await db.query(
      `INSERT INTO fraud_blacklist (nid_hash, reason, evidence_ref, reported_by)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (nid_hash) DO UPDATE SET
         reason = $2, evidence_ref = $3, active = TRUE, reported_at = NOW()`,
      [nid_hash, reason, evidence_ref || null, req.user.id]
    );

    // Apply fraud score penalty
    await creditScoreService.recordPaymentEvent(nid_hash, 'FRAUD_CONFIRMED');

    res.json({ success: true, message: 'Customer added to fraud blacklist' });
  })
);

// Admin: get score history for a customer
router.get(
  '/admin/history',
  authenticateToken,
  requireRole('admin'),
  query('nid_hash').isString().isLength({ min: 64, max: 64 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash } = req.query;
    const profile = await creditScoreService.lookupByNidHash(nid_hash);
    const events = await db.query(
      `SELECT event_type, score_delta, score_after, recorded_at
       FROM credit_score_events
       WHERE nid_hash = $1
       ORDER BY recorded_at DESC
       LIMIT 100`,
      [nid_hash]
    );

    res.json({
      profile: profile || { new_member: true },
      events: events.rows,
    });
  })
);

module.exports = router;
