const pool = require('../../config/database');
const logger = require('../../utils/logger');

class AdminDashboardService {
  async getDashboardStats() {
    const client = await pool.connect();
    try {
      const totalDevices = await client.query('SELECT COUNT(*) FROM devices WHERE status != $1', ['decoupled']);
      const overdueCount = await client.query(
        `SELECT COUNT(*) FROM devices d
         JOIN emi_agreements e ON d.id = e.device_id
         WHERE d.status NOT IN ('decoupled', 'unlocked')
         AND e.status = 'overdue'`
      );
      const lockedCount = await client.query(
        "SELECT COUNT(*) FROM devices WHERE status = 'locked'"
      );
      const decouplingPending = await client.query(
        "SELECT COUNT(*) FROM devices WHERE status = 'pending_decouple'"
      );
      const activeResellers = await client.query(
        "SELECT COUNT(*) FROM resellers WHERE status = 'active'"
      );
      const pendingResellers = await client.query(
        "SELECT COUNT(*) FROM resellers WHERE status = 'pending'"
      );
      const monthlyRevenue = await client.query(
        `SELECT COALESCE(SUM(amount), 0) as revenue
         FROM payments
         WHERE status = 'confirmed'
         AND created_at > NOW() - INTERVAL '30 days'`
      );
      const totalUsers = await client.query('SELECT COUNT(*) FROM users');

      return {
        totalDevices: parseInt(totalDevices.rows[0].count),
        overdueCount: parseInt(overdueCount.rows[0].count),
        lockedCount: parseInt(lockedCount.rows[0].count),
        decouplingPending: parseInt(decouplingPending.rows[0].count),
        activeResellers: parseInt(activeResellers.rows[0].count),
        pendingResellers: parseInt(pendingResellers.rows[0].count),
        monthlyRevenue: parseFloat(monthlyRevenue.rows[0].revenue),
        totalUsers: parseInt(totalUsers.rows[0].count)
      };
    } finally {
      client.release();
    }
  }

  async getResellers(filters = {}) {
    const client = await pool.connect();
    try {
      let query = `
        SELECT r.*,
          (SELECT COUNT(*) FROM dealers WHERE reseller_id = r.id) as dealer_count,
          (SELECT COUNT(*) FROM keys WHERE reseller_id = r.id AND status = 'consumed') as keys_consumed,
          (SELECT COALESCE(SUM(amount), 0) FROM payments WHERE reseller_id = r.id AND status = 'confirmed') as total_revenue
        FROM resellers r
        WHERE 1=1
      `;
      const params = [];
      let paramCount = 0;

      if (filters.status) {
        paramCount++;
        query += ` AND r.status = $${paramCount}`;
        params.push(filters.status);
      }

      if (filters.search) {
        paramCount++;
        query += ` AND (r.name ILIKE $${paramCount} OR r.email ILIKE $${paramCount})`;
        params.push(`%${filters.search}%`);
      }

      query += ' ORDER BY r.created_at DESC';

      if (filters.limit) {
        paramCount++;
        query += ` LIMIT $${paramCount}`;
        params.push(filters.limit);
      }

      if (filters.offset) {
        paramCount++;
        query += ` OFFSET $${paramCount}`;
        params.push(filters.offset);
      }

      const result = await client.query(query, params);

      let countQuery = `SELECT COUNT(*) FROM resellers r WHERE 1=1`;
      const countParams = [];
      let countParamCount = 0;

      if (filters.status) {
        countParamCount++;
        countQuery += ` AND r.status = $${countParamCount}`;
        countParams.push(filters.status);
      }

      if (filters.search) {
        countParamCount++;
        countQuery += ` AND (r.name ILIKE $${countParamCount} OR r.email ILIKE $${countParamCount})`;
        countParams.push(`%${filters.search}%`);
      }

      const countResult = await client.query(countQuery, countParams);

      return {
        resellers: result.rows,
        total: parseInt(countResult.rows[0].count)
      };
    } finally {
      client.release();
    }
  }

  async getResellerById(resellerId) {
    const client = await pool.connect();
    try {
      const result = await client.query(
        `SELECT r.*,
          (SELECT COUNT(*) FROM dealers WHERE reseller_id = r.id) as dealer_count,
          (SELECT COUNT(*) FROM keys WHERE reseller_id = r.id AND status = 'consumed') as keys_consumed
         FROM resellers r WHERE r.id = $1`,
        [resellerId]
      );
      return result.rows[0] || null;
    } finally {
      client.release();
    }
  }

  async approveReseller(resellerId, adminId, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const result = await client.query(
        `UPDATE resellers
         SET status = 'active', approved_at = NOW(), approved_by = $1, updated_at = NOW()
         WHERE id = $2 AND status = 'pending'
         RETURNING *`,
        [adminId, resellerId]
      );

      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Reseller not found or not pending approval' };
      }

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'RESELLER_APPROVED', 'reseller', $2, $3, $4, NOW())`,
        [adminId, resellerId, JSON.stringify({ resellerId, approvedAt: new Date() }), ipAddress]
      );

      await client.query('COMMIT');
      return { success: true, reseller: result.rows[0] };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to approve reseller:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async suspendReseller(resellerId, adminId, reason, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const result = await client.query(
        `UPDATE resellers
         SET status = 'suspended', suspended_at = NOW(), suspended_by = $1, suspension_reason = $2, updated_at = NOW()
         WHERE id = $3
         RETURNING *`,
        [adminId, reason, resellerId]
      );

      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Reseller not found' };
      }

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'RESELLER_SUSPENDED', 'reseller', $2, $3, $4, NOW())`,
        [adminId, resellerId, JSON.stringify({ resellerId, reason, suspendedAt: new Date() }), ipAddress]
      );

      await client.query('COMMIT');
      return { success: true, reseller: result.rows[0] };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to suspend reseller:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async setResellerQuota(resellerId, monthlyQuota, adminId, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const result = await client.query(
        `UPDATE resellers
         SET monthly_key_quota = $1, quota_updated_at = NOW(), quota_updated_by = $2, updated_at = NOW()
         WHERE id = $3
         RETURNING *`,
        [monthlyQuota, adminId, resellerId]
      );

      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Reseller not found' };
      }

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'RESELLER_QUOTA_UPDATED', 'reseller', $2, $3, $4, NOW())`,
        [adminId, resellerId, JSON.stringify({ resellerId, monthlyQuota, updatedAt: new Date() }), ipAddress]
      );

      await client.query('COMMIT');
      return { success: true, reseller: result.rows[0] };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to set reseller quota:', error);
      throw error;
    } finally {
      client.release();
    }
  }
  async getDevices({ page = 1, limit = 20, status, dealerId } = {}) {
    const client = await pool.connect();
    try {
      const offset = (page - 1) * limit;
      const conditions = [];
      const params = [];
      let idx = 1;

      if (status) { conditions.push(`d.status = $${idx++}`); params.push(status); }
      if (dealerId) { conditions.push(`d.dealer_id = $${idx++}`); params.push(dealerId); }

      const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

      const rows = await client.query(
        `SELECT d.id, d.imei, d.device_name, d.model, d.brand, d.status, d.lock_level,
                d.created_at, d.updated_at, dl.name as dealer_name
         FROM devices d
         LEFT JOIN dealers dl ON d.dealer_id = dl.id
         ${where} ORDER BY d.created_at DESC LIMIT $${idx++} OFFSET $${idx}`,
        [...params, limit, offset]
      );

      const countResult = await client.query(
        `SELECT COUNT(*) FROM devices d ${where}`, params
      );
      const total = parseInt(countResult.rows[0].count, 10);

      return {
        devices: rows.rows,
        pagination: { page, limit, total, pages: Math.ceil(total / limit) }
      };
    } finally {
      client.release();
    }
  }

  async deleteUser(userId, deletedBy, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Soft-delete: never hard-delete user records (GDPR compliance)
      const result = await client.query(
        `UPDATE users
         SET deleted_at = NOW(), deleted_by = $1, status = 'deleted', updated_at = NOW()
         WHERE id = $2 AND deleted_at IS NULL
         RETURNING id, email`,
        [deletedBy, userId]
      );

      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'User not found or already deleted' };
      }

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'USER_SOFT_DELETED', 'user', $2, $3, $4, NOW())`,
        [deletedBy, userId, JSON.stringify({ targetUserId: userId, email: result.rows[0].email }), ipAddress]
      );

      await client.query('COMMIT');
      return { success: true, userId };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to soft-delete user:', error);
      throw error;
    } finally {
      client.release();
    }
  }
}

module.exports = new AdminDashboardService();