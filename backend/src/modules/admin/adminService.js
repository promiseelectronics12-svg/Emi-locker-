const db = require('../../config/database');
const pool = db.pool;
const logger = require('../../utils/logger');
const redis = require('../../config/redis');
const crypto = require('crypto');

class AdminDashboardService {
  async getDashboardStats() {
    const cacheKey = 'admin:dashboard:stats';
    try {
      const cached = await redis.get(cacheKey);
      if (cached) return JSON.parse(cached);
    } catch (_) {}

    const client = await pool.connect();
    try {
      const [
        totalDevices, lockedCount, decouplingPending, totalUsers,
        monthlyRevenue, activeAlerts, recentEvents, activeResellers, pendingResellers
      ] = await Promise.all([
        client.query("SELECT COUNT(*) FROM devices WHERE status != 'decoupled'"),
        client.query("SELECT COUNT(*) FROM devices WHERE status = 'locked'"),
        client.query("SELECT COUNT(*) FROM devices WHERE status = 'pending_decouple'"),
        client.query('SELECT COUNT(*) FROM users'),
        client.query(`SELECT COALESCE(SUM(amount), 0) as revenue FROM emi_payments WHERE recorded_at > NOW() - INTERVAL '30 days'`),
        client.query("SELECT COUNT(*) FROM security_events WHERE created_at > NOW() - INTERVAL '7 days'"),
        client.query("SELECT id, event_type as type, severity, created_at as timestamp FROM security_events ORDER BY created_at DESC LIMIT 5"),
        client.query("SELECT COUNT(*) FROM resellers WHERE status = 'active'"),
        client.query("SELECT COUNT(*) FROM resellers WHERE status = 'pending'"),
      ]);

      const stats = {
        totalDevices: parseInt(totalDevices.rows[0].count),
        overdueCount: 0,
        lockedCount: parseInt(lockedCount.rows[0].count),
        decouplingPending: parseInt(decouplingPending.rows[0].count),
        activeResellers: parseInt(activeResellers.rows[0].count),
        pendingResellers: parseInt(pendingResellers.rows[0].count),
        monthlyRevenue: parseFloat(monthlyRevenue.rows[0].revenue),
        totalUsers: parseInt(totalUsers.rows[0].count),
        activeAlerts: parseInt(activeAlerts.rows[0].count),
        recentEvents: recentEvents.rows
      };

      try { await redis.setex(cacheKey, 300, JSON.stringify(stats)); } catch (_) {}
      return stats;
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
          (SELECT COUNT(*) FROM activation_keys WHERE reseller_id = r.id AND status = 'activated') as keys_consumed,
          0::numeric as total_revenue
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
        resellers: result.rows.map(row => ({
          ...row,
          monthlyQuota: Number(row.monthly_key_quota ?? row.monthly_quota ?? 0),
          usedQuota: Number(row.used_keys ?? 0),
          activatedKeys: Number(row.keys_consumed ?? 0),
          dealerCount: row.dealer_count,
          totalRevenue: row.total_revenue
        })),
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
          (SELECT COUNT(*) FROM activation_keys WHERE reseller_id = r.id AND status = 'activated') as keys_consumed
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
         SET monthly_quota = $1,
             monthly_key_quota = $1,
             quota_updated_at = NOW(),
             quota_updated_by = $2,
             updated_at = NOW()
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

  async getDealers(filters = {}) {
    const client = await pool.connect();
    try {
      let query = `
        SELECT d.*,
          r.name as reseller_name,
          (SELECT COUNT(*) FROM devices WHERE dealer_id = d.id) as device_count
        FROM dealers d
        LEFT JOIN resellers r ON d.reseller_id = r.id
        WHERE 1=1
      `;
      const params = [];
      let p = 0;

      if (filters.status) { query += ` AND d.status = $${++p}`; params.push(filters.status); }
      if (filters.resellerId) { query += ` AND d.reseller_id = $${++p}`; params.push(filters.resellerId); }
      if (filters.search) {
        query += ` AND (d.name ILIKE $${++p} OR d.phone ILIKE $${p} OR d.email ILIKE $${p})`;
        params.push(`%${filters.search}%`);
      }

      query += ' ORDER BY d.created_at DESC';

      const limit = Math.min(parseInt(filters.limit) || 50, 200);
      const offset = parseInt(filters.offset) || 0;
      query += ` LIMIT $${++p} OFFSET $${++p}`;
      params.push(limit, offset);

      const result = await client.query(query, params);

      let countQ = `SELECT COUNT(*) FROM dealers d WHERE 1=1`;
      const countP = [];
      let cp = 0;
      if (filters.status) { countQ += ` AND d.status = $${++cp}`; countP.push(filters.status); }
      if (filters.resellerId) { countQ += ` AND d.reseller_id = $${++cp}`; countP.push(filters.resellerId); }
      if (filters.search) { countQ += ` AND (d.name ILIKE $${++cp} OR d.phone ILIKE $${cp} OR d.email ILIKE $${cp})`; countP.push(`%${filters.search}%`); }

      const countResult = await client.query(countQ, countP);
      return { dealers: result.rows, total: parseInt(countResult.rows[0].count), limit, offset };
    } finally {
      client.release();
    }
  }

  async suspendDealer(dealerId, adminId, reason, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `UPDATE dealers SET status = 'suspended', updated_at = NOW() WHERE id = $1 RETURNING *`,
        [dealerId]
      );
      if (!result.rows.length) { await client.query('ROLLBACK'); return { success: false, error: 'Dealer not found' }; }
      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'DEALER_SUSPENDED', 'dealer', $2, $3, $4, NOW())`,
        [adminId, dealerId, JSON.stringify({ reason }), ipAddress]
      );
      await client.query('COMMIT');
      return { success: true, dealer: result.rows[0] };
    } catch (err) {
      await client.query('ROLLBACK'); throw err;
    } finally {
      client.release();
    }
  }

  async activateDealer(dealerId, adminId, ipAddress) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query(
        `UPDATE dealers SET status = 'active', updated_at = NOW() WHERE id = $1 RETURNING *`,
        [dealerId]
      );
      if (!result.rows.length) { await client.query('ROLLBACK'); return { success: false, error: 'Dealer not found' }; }
      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'DEALER_ACTIVATED', 'dealer', $2, $3, $4, NOW())`,
        [adminId, dealerId, JSON.stringify({}), ipAddress]
      );
      await client.query('COMMIT');
      return { success: true, dealer: result.rows[0] };
    } catch (err) {
      await client.query('ROLLBACK'); throw err;
    } finally {
      client.release();
    }
  }

  async universalSearch(q) {
    if (!q || q.trim().length < 2) return { devices: [], dealers: [], resellers: [] };
    const term = `%${q.trim()}%`;
    const client = await pool.connect();
    try {
      const [devices, dealers, resellers] = await Promise.all([
        client.query(
          `SELECT d.id, d.imei, d.model, d.brand, d.status,
                  u.name as owner_name, u.phone as owner_phone, dl.name as dealer_name
           FROM devices d
           LEFT JOIN users u ON d.owner_id = u.id
           LEFT JOIN dealers dl ON d.dealer_id = dl.id
           WHERE d.imei ILIKE $1 OR d.model ILIKE $1 OR u.name ILIKE $1 OR u.phone ILIKE $1
           LIMIT 20`,
          [term]
        ),
        client.query(
          `SELECT id, name, phone, email, status FROM dealers WHERE name ILIKE $1 OR phone ILIKE $1 OR email ILIKE $1 LIMIT 10`,
          [term]
        ),
        client.query(
          `SELECT id, name, phone, email, status FROM resellers WHERE name ILIKE $1 OR phone ILIKE $1 OR email ILIKE $1 LIMIT 10`,
          [term]
        ),
      ]);
      return { devices: devices.rows, dealers: dealers.rows, resellers: resellers.rows };
    } finally {
      client.release();
    }
  }

  async inviteReseller(email, name, adminId) {
    const token = crypto.randomBytes(24).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const key = `reseller_invite:${tokenHash}`;

    await redis.setex(key, 60 * 60 * 48, JSON.stringify({ email, name, invitedBy: adminId, createdAt: new Date().toISOString() }));

    const emailService = require('../notifications/emailService');
    const inviteUrl = `${process.env.ADMIN_PANEL_URL || 'http://localhost:5173'}/reseller-onboard?token=${token}`;
    await emailService.sendResellerInvite(email, name, inviteUrl);

    return { success: true, email, name };
  }

  async verifyResellerInviteToken(token) {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const key = `reseller_invite:${tokenHash}`;
    const raw = await redis.get(key);
    if (!raw) return null;
    return JSON.parse(raw);
  }

  async consumeResellerInviteToken(token, passwordHash, photoUrl) {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const key = `reseller_invite:${tokenHash}`;
    const raw = await redis.get(key);
    if (!raw) return { success: false, error: 'Invalid or expired invite token' };

    const invite = JSON.parse(raw);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      // Upsert user row (auth lives in users table, role = reseller)
      const userResult = await client.query(
        `INSERT INTO users (email, password_hash, name, role, status, created_at, updated_at)
         VALUES ($1, $2, $3, 'reseller', 'active', NOW(), NOW())
         ON CONFLICT (email) DO UPDATE
           SET password_hash = EXCLUDED.password_hash,
               status = 'active', updated_at = NOW()
         RETURNING id, name, email, status`,
        [invite.email, passwordHash, invite.name]
      );
      const user = userResult.rows[0];

      // Upsert reseller profile row (id mirrors user.id)
      await client.query(
        `INSERT INTO resellers (id, name, email, status, created_at, updated_at)
         VALUES ($1, $2, $3, 'active', NOW(), NOW())
         ON CONFLICT (id) DO UPDATE
           SET name = EXCLUDED.name, status = 'active', updated_at = NOW()`,
        [user.id, invite.name, invite.email]
      );

      await client.query('COMMIT');
      await redis.del(key);
      return { success: true, reseller: user };
    } catch (err) {
      await client.query('ROLLBACK'); throw err;
    } finally {
      client.release();
    }
  }

  async getKeyInventory(filters = {}) {
    const client = await pool.connect();
    try {
      let query = `
        SELECT ak.tier,
          ak.reseller_id,
          r.name as reseller_name,
          COUNT(*) FILTER (WHERE ak.status = 'available') as available,
          COUNT(*) FILTER (WHERE ak.status = 'assigned') as assigned,
          COUNT(*) FILTER (WHERE ak.status = 'activated') as activated,
          COUNT(*) FILTER (WHERE ak.status = 'revoked') as revoked,
          COUNT(*) as total
        FROM activation_keys ak
        LEFT JOIN resellers r ON ak.reseller_id = r.id
        WHERE 1=1
      `;
      const params = [];
      let p = 0;
      if (filters.tier) { query += ` AND ak.tier = $${++p}`; params.push(filters.tier); }
      if (filters.resellerId) { query += ` AND ak.reseller_id = $${++p}`; params.push(filters.resellerId); }
      query += ' GROUP BY ak.tier, ak.reseller_id, r.name ORDER BY ak.tier, r.name';

      const result = await client.query(query, params);
      return result.rows.map(row => ({
        tier: row.tier,
        resellerId: row.reseller_id,
        resellerName: row.reseller_name,
        available: parseInt(row.available),
        assigned: parseInt(row.assigned),
        activated: parseInt(row.activated),
        revoked: parseInt(row.revoked),
        total: parseInt(row.total),
      }));
    } finally {
      client.release();
    }
  }

  // ── District Map & Reseller Distribution ─────────────────────────────────

  async getDistrictSummary() {
    const result = await pool.query(`
      SELECT
        COALESCE(r.district, 'Unknown') AS district,
        COUNT(DISTINCT r.id)::int AS reseller_count,
        COUNT(ak.id) FILTER (WHERE ak.status IN ('activated','assigned'))::int AS total_keys_distributed
      FROM resellers r
      LEFT JOIN activation_keys ak ON ak.reseller_id = r.id
      GROUP BY COALESCE(r.district, 'Unknown')
      ORDER BY total_keys_distributed DESC
    `);
    return result.rows;
  }

  async getResellersByDistrict(district) {
    const result = await pool.query(`
      SELECT
        r.id, r.name, r.status, r.district,
        COUNT(DISTINCT d.id)::int AS dealer_count,
        COUNT(ak.id) FILTER (WHERE ak.status IN ('activated','assigned'))::int AS keys_distributed
      FROM resellers r
      LEFT JOIN dealers d ON d.reseller_id = r.id
      LEFT JOIN activation_keys ak ON ak.reseller_id = r.id
      WHERE r.district = $1
      GROUP BY r.id
      ORDER BY keys_distributed DESC
    `, [district]);
    return result.rows;
  }

  async getResellerStats(resellerId) {
    const client = await pool.connect();
    try {
      const [resellerResult, monthlyResult, dealerResult] = await Promise.all([
        client.query('SELECT * FROM resellers WHERE id = $1', [resellerId]),
        client.query(`
          SELECT
            TO_CHAR(DATE_TRUNC('month', ak.created_at), 'YYYY-MM') AS month,
            COUNT(*) FILTER (WHERE ak.status IN ('activated','assigned'))::int AS keys_distributed
          FROM activation_keys ak
          WHERE ak.reseller_id = $1
            AND ak.created_at >= NOW() - INTERVAL '12 months'
          GROUP BY month
          ORDER BY month ASC
        `, [resellerId]),
        client.query(`
          SELECT
            d.id, d.name, d.phone,
            COUNT(ak.id) FILTER (WHERE ak.status = 'activated')::int AS keys_consumed,
            COUNT(DISTINCT ak.device_id)::int AS devices_bound,
            MAX(ak.updated_at) AS last_active
          FROM dealers d
          LEFT JOIN activation_keys ak ON ak.dealer_id = d.id
          WHERE d.reseller_id = $1
          GROUP BY d.id
          ORDER BY keys_consumed DESC
        `, [resellerId]),
      ]);

      if (resellerResult.rows.length === 0) return null;

      const allMonths = monthlyResult.rows;
      return {
        reseller: resellerResult.rows[0],
        monthly: allMonths.slice(-6),
        yearly: allMonths,
        dealers: dealerResult.rows,
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
