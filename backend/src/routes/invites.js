const express = require('express');
const crypto = require('crypto');
const { body, validationResult } = require('express-validator');
const db = require('../config/database');
const { authenticateToken, requireMinRole } = require('../middleware/auth');
const logger = require('../utils/logger');

const router = express.Router();

function validateRequest(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ success: false, errors: errors.array() });
  }
  next();
}

/**
 * POST /api/v1/admin/invites
 * Admin or reseller creates a dealer/reseller invite.
 * Returns the raw token ONCE — never stored, only the SHA-256 hash is kept.
 */
router.post(
  '/',
  authenticateToken,
  requireMinRole('reseller'),
  body('email').isEmail().normalizeEmail().withMessage('Valid email required'),
  body('role').isIn(['dealer', 'reseller']).withMessage('role must be dealer or reseller'),
  body('reseller_id').optional().isUUID(),
  validateRequest,
  async (req, res) => {
    try {
      const { email, role, reseller_id } = req.body;
      const invitedBy = req.user.id;

      // Check email not already a registered user
      const existing = await db.query(
        'SELECT id FROM users WHERE email = $1 LIMIT 1',
        [email.toLowerCase().trim()]
      );
      if (existing.rows.length) {
        return res.status(409).json({ success: false, error: 'Email already registered' });
      }

      // Check no unexpired/unused invite for this email
      const dupeInvite = await db.query(
        `SELECT id FROM dealer_invites
         WHERE email = $1 AND used_at IS NULL AND expires_at > NOW()
         LIMIT 1`,
        [email.toLowerCase().trim()]
      );
      if (dupeInvite.rows.length) {
        return res.status(409).json({ success: false, error: 'Active invite already exists for this email' });
      }

      // Generate one-time token — 32 random bytes, base64url encoded
      const rawToken = crypto.randomBytes(32).toString('base64url');
      const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
      const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000); // 48 hours

      const result = await db.query(
        `INSERT INTO dealer_invites
           (token_hash, email, role, invited_by, reseller_id, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, email, role, expires_at`,
        [
          tokenHash,
          email.toLowerCase().trim(),
          role,
          invitedBy,
          reseller_id || null,
          expiresAt
        ]
      );

      const invite = result.rows[0];
      logger.info('Dealer invite created', { inviteId: invite.id, email: invite.email, role: invite.role });

      return res.status(201).json({
        success: true,
        invite_id: invite.id,
        email: invite.email,
        role: invite.role,
        expires_at: invite.expires_at,
        // Raw token returned ONCE — send via email/deep link
        token: rawToken
      });
    } catch (error) {
      logger.error('Create invite failed', { error: error.message });
      return res.status(500).json({ success: false, error: 'Failed to create invite' });
    }
  }
);

/**
 * GET /api/v1/admin/invites
 * Lists pending invites (admin/reseller scope).
 */
router.get(
  '/',
  authenticateToken,
  requireMinRole('reseller'),
  async (req, res) => {
    try {
      const result = await db.query(
        `SELECT id, email, role, expires_at, used_at,
                CASE WHEN used_at IS NOT NULL THEN 'used'
                     WHEN expires_at < NOW() THEN 'expired'
                     ELSE 'pending'
                END AS status
         FROM dealer_invites
         WHERE invited_by = $1
         ORDER BY created_at DESC
         LIMIT 50`,
        [req.user.id]
      );
      return res.json({ success: true, invites: result.rows });
    } catch (error) {
      return res.status(500).json({ success: false, error: 'Failed to list invites' });
    }
  }
);

/**
 * DELETE /api/v1/admin/invites/:id
 * Revoke a pending (unused, unexpired) invite.
 */
router.delete(
  '/:id',
  authenticateToken,
  requireMinRole('reseller'),
  async (req, res) => {
    try {
      const result = await db.query(
        `DELETE FROM dealer_invites
         WHERE id = $1 AND invited_by = $2 AND used_at IS NULL
         RETURNING id`,
        [req.params.id, req.user.id]
      );
      if (!result.rows.length) {
        return res.status(404).json({ success: false, error: 'Invite not found or already used' });
      }
      return res.json({ success: true });
    } catch (error) {
      return res.status(500).json({ success: false, error: 'Failed to revoke invite' });
    }
  }
);

/**
 * Exported middleware: validates invite_token in request body.
 * Used by auth routes to optionally require invite before registration.
 * When REQUIRE_INVITE=true, token is mandatory and must be valid.
 */
async function validateInviteMiddleware(req, res, next) {
  const requireInvite = process.env.REQUIRE_INVITE === 'true';
  const rawToken = req.body?.invite_token;

  if (!requireInvite && !rawToken) {
    // Open registration mode (dev/demo) — skip invite check
    return next();
  }

  if (!rawToken) {
    return res.status(403).json({
      success: false,
      error: 'Invite token required. Contact admin for an invitation.'
    });
  }

  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');

  const result = await db.query(
    `SELECT id, email, role, reseller_id
     FROM dealer_invites
     WHERE token_hash = $1
       AND used_at IS NULL
       AND expires_at > NOW()
     LIMIT 1`,
    [tokenHash]
  );

  if (!result.rows.length) {
    return res.status(403).json({
      success: false,
      error: 'Invalid or expired invite token.'
    });
  }

  const invite = result.rows[0];

  // Email must match what was invited
  const requestEmail = (req.body?.email || '').toLowerCase().trim();
  if (requestEmail !== invite.email) {
    return res.status(403).json({
      success: false,
      error: 'Email does not match the invited email address.'
    });
  }

  // Attach invite to request for the registration handler to consume
  req.validatedInvite = invite;
  next();
}

/**
 * Marks invite as used. Call AFTER successful user creation.
 */
async function consumeInvite(inviteId, userId) {
  await db.query(
    `UPDATE dealer_invites SET used_at = NOW(), used_by = $2 WHERE id = $1`,
    [inviteId, userId]
  );
}

module.exports = router;
module.exports.validateInviteMiddleware = validateInviteMiddleware;
module.exports.consumeInvite = consumeInvite;
