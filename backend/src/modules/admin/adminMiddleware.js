const logger = require('../../utils/logger');
const db = require('../../config/database');

const adminMiddleware = {
  requireVerified2FA: async (req, res, next) => {
    if (!req.user || req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const db = require('../../config/database');

    try {
      const result = await db.query(
        'SELECT two_factor_verified, two_factor_verified_at FROM users WHERE id = $1',
        [req.user.id]
      );

      if (result.rows.length === 0) {
        return res.status(401).json({ error: 'User not found' });
      }

      const user = result.rows[0];

      if (!user.two_factor_verified) {
        return res.status(403).json({
          error: '2FA verification required',
          code: '2FA_REQUIRED',
          message: 'Please verify your identity with 2FA before accessing admin functions'
        });
      }

      const verifiedAt = new Date(user.two_factor_verified_at);
      const now = new Date();
      const diffMinutes = (now - verifiedAt) / (1000 * 60);

      if (diffMinutes > 30) {
        return res.status(403).json({
          error: '2FA session expired',
          code: '2FA_SESSION_EXPIRED',
          message: 'Please re-verify your identity with 2FA'
        });
      }

      next();
    } catch (error) {
      console.error('2FA verification check failed:', error);
      return res.status(500).json({ error: 'Failed to verify 2FA session' });
    }
  },

  verifyAdminRole: async (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (req.user.role !== 'admin') {
      return res.status(403).json({
        error: 'Admin access required',
        requiredRole: 'admin',
        actualRole: req.user.role
      });
    }

    // Secondary DB-verified role check — prevents token role spoofing
    try {
      const result = await db.query(`SELECT role FROM users WHERE id = $1 AND deleted_at IS NULL`, [req.user.id]);
      if (!result.rows.length || result.rows[0].role !== 'admin') {
        return res.status(403).json({ error: 'Admin role not confirmed' });
      }
    } catch (err) {
      logger.error('Admin role DB verification failed:', err);
      return res.status(500).json({ error: 'Internal server error' });
    }

    next();
  },

  logAdminAction: async (req, res, next) => {
    const startTime = Date.now();

    res.on('finish', () => {
      const duration = Date.now() - startTime;
      // Use module-level db import — no inline require
      const action = req.route ? req.route.path : req.path;
      const method = req.method;
      const statusCode = res.statusCode;

      if (req.user && req.user.id) {
        db.query(
          `INSERT INTO admin_action_log (admin_id, action, method, path, status_code, duration_ms, ip_address, user_agent, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
          [req.user.id, action, method, req.originalUrl, statusCode, duration, req.ip, req.get('User-Agent')]
        ).catch(err => {
          logger.error('Failed to log admin action:', err);
        });
      }
    });

    next();
  }
};

module.exports = adminMiddleware;