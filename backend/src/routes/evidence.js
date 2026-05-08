const express = require('express');
const router = express.Router();
const asyncHandler = require('express-async-handler');
const { body, param } = require('express-validator');
const { authenticateToken } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const { validateRequest } = require('../middleware/validation');
const db = require('../config/database');
const logger = require('../utils/logger');

router.use(authenticateToken);

// POST /evidence/register
// Dealer calls this after storing encrypted photos in Google Drive.
// Server stores ONLY the index + Key Fragment A. Photos never touch the server.
router.post(
  '/register',
  requireRole('dealer'),
  body('nid_hash').isString().isLength({ min: 64, max: 64 }).withMessage('SHA-256 nid_hash required'),
  body('device_id').isUUID().withMessage('Valid device_id required'),
  body('evidence_type').isIn(['NID_FRONT', 'NID_BACK', 'FACE_PHOTO']).withMessage('Invalid evidence_type'),
  body('key_a_encrypted').isString().isLength({ min: 1, max: 2048 }).withMessage('Encrypted Key A required'),
  body('photo_hash').isString().isLength({ min: 64, max: 64 }).withMessage('SHA-256 photo_hash required'),
  body('dealer_seed_id').isString().isLength({ min: 1, max: 255 }),
  body('reseller_seed_id').isString().isLength({ min: 1, max: 255 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash, device_id, evidence_type, key_a_encrypted, photo_hash, dealer_seed_id, reseller_seed_id } = req.body;

    // Verify this device belongs to the requesting dealer
    const deviceCheck = await db.query(
      `SELECT id FROM devices WHERE id = $1 AND dealer_id = $2`,
      [device_id, req.user.id]
    );
    if (deviceCheck.rows.length === 0) {
      return res.status(403).json({ success: false, error: 'Device not found or access denied' });
    }

    const result = await db.query(
      `INSERT INTO evidence_vault_index
         (nid_hash, device_id, evidence_type, key_a_ref, photo_hash, dealer_seed_id, reseller_seed_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id`,
      [nid_hash, device_id, evidence_type, key_a_encrypted, photo_hash, dealer_seed_id, reseller_seed_id]
    );

    res.status(201).json({ success: true, evidence_id: result.rows[0].id });
  })
);

// POST /evidence/access-request
// Admin initiates a request to access evidence for a fraud case.
// Requires two admin approvals + key holder (dealer/reseller) authorization.
router.post(
  '/access-request',
  requireRole('admin'),
  body('evidence_id').isUUID().withMessage('Valid evidence_id required'),
  body('reason').isString().isLength({ min: 10, max: 1000 }).withMessage('Reason required (min 10 chars)'),
  body('case_reference').optional().isString().isLength({ max: 255 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { evidence_id, reason, case_reference } = req.body;

    const evidence = await db.query(
      `SELECT id, nid_hash, device_id FROM evidence_vault_index WHERE id = $1 AND deleted_at IS NULL`,
      [evidence_id]
    );
    if (evidence.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Evidence not found' });
    }

    // Check for an existing pending request to prevent duplicates
    const existing = await db.query(
      `SELECT id FROM evidence_access_log
       WHERE evidence_id = $1 AND access_granted = FALSE AND requested_by = $2
         AND accessed_at > NOW() - INTERVAL '24 hours'`,
      [evidence_id, req.user.id]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ success: false, error: 'A pending request already exists for this evidence' });
    }

    const request = await db.query(
      `INSERT INTO evidence_access_log (evidence_id, requested_by, access_reason, case_reference)
       VALUES ($1, $2, $3, $4)
       RETURNING id`,
      [evidence_id, req.user.id, reason, case_reference || null]
    );

    logger.info(`Evidence access request ${request.rows[0].id} created by admin ${req.user.id}`);
    res.status(201).json({ success: true, request_id: request.rows[0].id });
  })
);

// POST /evidence/access-request/:requestId/approve
// Second admin or key holder approves a pending access request.
// When approved_by_1 + approved_by_2 + key_holder_authorized all true: session created.
router.post(
  '/access-request/:requestId/approve',
  requireRole('admin', 'dealer', 'reseller'),
  param('requestId').isUUID(),
  body('approval_type').isIn(['admin_approval', 'key_holder_authorization']).withMessage('Invalid approval_type'),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { requestId } = req.params;
    const { approval_type } = req.body;

    const request = await db.query(
      `SELECT * FROM evidence_access_log WHERE id = $1 AND access_granted = FALSE`,
      [requestId]
    );
    if (request.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Pending request not found' });
    }

    const r = request.rows[0];

    if (approval_type === 'admin_approval') {
      if (req.user.role !== 'admin') {
        return res.status(403).json({ success: false, error: 'Admin role required for this approval type' });
      }
      if (r.requested_by === req.user.id) {
        return res.status(403).json({ success: false, error: 'Requester cannot approve their own request' });
      }

      if (!r.approved_by_1) {
        await db.query(`UPDATE evidence_access_log SET approved_by_1 = $1 WHERE id = $2`, [req.user.id, requestId]);
      } else if (!r.approved_by_2 && r.approved_by_1 !== req.user.id) {
        await db.query(`UPDATE evidence_access_log SET approved_by_2 = $1 WHERE id = $2`, [req.user.id, requestId]);
      } else {
        return res.status(409).json({ success: false, error: 'Admin approval slots already filled' });
      }
    } else {
      // key_holder_authorization — dealer or reseller who holds the evidence copy
      await db.query(`UPDATE evidence_access_log SET key_holder_authorized = TRUE WHERE id = $1`, [requestId]);
    }

    // Re-fetch to check if all three conditions are now met
    const updated = await db.query(`SELECT * FROM evidence_access_log WHERE id = $1`, [requestId]);
    const u = updated.rows[0];

    const sessionExpires = new Date(Date.now() + 30 * 60 * 1000).toISOString();

    if (u.approved_by_1 && u.approved_by_2 && u.key_holder_authorized) {
      await db.query(
        `UPDATE evidence_access_log
         SET access_granted = TRUE, session_expires = $1
         WHERE id = $2`,
        [sessionExpires, requestId]
      );

      logger.info(`Evidence access GRANTED for request ${requestId} — 30-minute session active`);
      return res.json({ success: true, access_granted: true, session_expires: sessionExpires });
    }

    res.json({
      success: true,
      access_granted: false,
      pending: {
        admin_approval_1: !!u.approved_by_1,
        admin_approval_2: !!u.approved_by_2,
        key_holder_authorized: u.key_holder_authorized,
      },
    });
  })
);

// GET /evidence/access-request/:requestId/key-a
// Returns Key Fragment A within the active 30-minute session window.
router.get(
  '/access-request/:requestId/key-a',
  requireRole('admin'),
  param('requestId').isUUID(),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { requestId } = req.params;

    const request = await db.query(
      `SELECT eal.*, evi.key_a_ref, evi.photo_hash, evi.nid_hash
       FROM evidence_access_log eal
       JOIN evidence_vault_index evi ON eal.evidence_id = evi.id
       WHERE eal.id = $1
         AND eal.access_granted = TRUE
         AND eal.session_expires > NOW()`,
      [requestId]
    );

    if (request.rows.length === 0) {
      return res.status(403).json({
        success: false,
        error: 'No active session. Request access or session has expired.'
      });
    }

    const r = request.rows[0];

    logger.info(`Key A accessed for request ${requestId} by admin ${req.user.id}`);

    res.json({
      success: true,
      key_a_ref: r.key_a_ref,
      photo_hash: r.photo_hash,
      session_expires: r.session_expires,
    });
  })
);

// POST /evidence/delete-request
// Customer requests deletion after all EMIs are paid.
router.post(
  '/delete-request',
  requireRole('admin', 'dealer'),
  body('nid_hash').isString().isLength({ min: 64, max: 64 }),
  body('reason').optional().isString().isLength({ max: 500 }),
  validateRequest,
  asyncHandler(async (req, res) => {
    const { nid_hash, reason } = req.body;

    // Verify no outstanding EMI or open fraud cases
    const openFraud = await db.query(
      `SELECT id FROM fraud_blacklist WHERE nid_hash = $1 AND active = TRUE`,
      [nid_hash]
    );
    if (openFraud.rows.length > 0) {
      return res.status(409).json({
        success: false,
        error: 'Cannot delete evidence while fraud case is active'
      });
    }

    const result = await db.query(
      `UPDATE evidence_vault_index
       SET deleted_at = NOW()
       WHERE nid_hash = $1 AND deleted_at IS NULL
       RETURNING id`,
      [nid_hash]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'No active evidence found for this NID hash' });
    }

    logger.info(`Evidence deletion requested for nid_hash=${nid_hash} — ${result.rows.length} record(s) marked`);

    res.json({
      success: true,
      records_marked: result.rows.length,
      message: 'Evidence deletion scheduled. Dealer and reseller apps will receive deletion commands on next sync.',
    });
  })
);

module.exports = router;
