const db = require('../../config/database');
const logger = require('../../utils/logger');

class AdminDeviceService {
  async getAllDevices(filters = {}) {
    const client = await db.connect();
    try {
      let query = `
        SELECT d.*,
          u.name as owner_name, u.phone as owner_phone, u.email as owner_email,
          dl.name as dealer_name, dl.phone as dealer_phone,
          r.name as reseller_name,
          e.status as emi_status, e.monthly_amount, e.next_payment_date,
          (SELECT COUNT(*) FROM payments p WHERE p.device_id = d.id AND p.status = 'confirmed') as payment_count,
          (SELECT MAX(p.created_at) FROM payments p WHERE p.device_id = d.id AND p.status = 'confirmed') as last_payment_date
        FROM devices d
        LEFT JOIN users u ON d.owner_id = u.id
        LEFT JOIN dealers dl ON d.dealer_id = dl.id
        LEFT JOIN resellers r ON dl.reseller_id = r.id
        LEFT JOIN emi_agreements e ON d.id = e.device_id
        WHERE d.status != 'decoupled'
      `;

      const params = [];
      let paramCount = 0;

      if (filters.status) {
        paramCount++;
        query += ` AND d.status = $${paramCount}`;
        params.push(filters.status);
      }

      if (filters.dealerId) {
        paramCount++;
        query += ` AND d.dealer_id = $${paramCount}`;
        params.push(filters.dealerId);
      }

      if (filters.resellerId) {
        paramCount++;
        query += ` AND dl.reseller_id = $${paramCount}`;
        params.push(filters.resellerId);
      }

      if (filters.imei) {
        paramCount++;
        query += ` AND d.imei ILIKE $${paramCount}`;
        params.push(`%${filters.imei}%`);
      }

      if (filters.search) {
        paramCount++;
        query += ` AND (u.name ILIKE $${paramCount} OR u.phone ILIKE $${paramCount} OR d.imei ILIKE $${paramCount} OR d.model ILIKE $${paramCount})`;
        params.push(`%${filters.search}%`);
      }

      if (filters.emiStatus) {
        paramCount++;
        query += ` AND e.status = $${paramCount}`;
        params.push(filters.emiStatus);
      }

      query += ' ORDER BY d.created_at DESC';

      if (filters.limit) {
        paramCount++;
        query += ` LIMIT $${paramCount}`;
        params.push(filters.limit);
      } else {
        query += ' LIMIT 100';
      }

      if (filters.offset) {
        paramCount++;
        query += ` OFFSET $${paramCount}`;
        params.push(filters.offset);
      }

      const result = await client.query(query, params);

      let countQuery = `SELECT COUNT(*) FROM devices d
        LEFT JOIN users u ON d.owner_id = u.id
        LEFT JOIN dealers dl ON d.dealer_id = dl.id
        LEFT JOIN emi_agreements e ON d.id = e.device_id
        WHERE d.status != 'decoupled'`;
      const countParams = [];
      let countParamCount = 0;

      if (filters.status) {
        countParamCount++;
        countQuery += ` AND d.status = $${countParamCount}`;
        countParams.push(filters.status);
      }

      if (filters.dealerId) {
        countParamCount++;
        countQuery += ` AND d.dealer_id = $${countParamCount}`;
        countParams.push(filters.dealerId);
      }

      if (filters.resellerId) {
        countParamCount++;
        countQuery += ` AND dl.reseller_id = $${countParamCount}`;
        countParams.push(filters.resellerId);
      }

      if (filters.imei) {
        countParamCount++;
        countQuery += ` AND d.imei ILIKE $${countParamCount}`;
        countParams.push(`%${filters.imei}%`);
      }

      if (filters.search) {
        countParamCount++;
        countQuery += ` AND (u.name ILIKE $${countParamCount} OR u.phone ILIKE $${countParamCount} OR d.imei ILIKE $${countParamCount} OR d.model ILIKE $${countParamCount})`;
        countParams.push(`%${filters.search}%`);
      }

      if (filters.emiStatus) {
        countParamCount++;
        countQuery += ` AND e.status = $${countParamCount}`;
        countParams.push(filters.emiStatus);
      }

      const countResult = await client.query(countQuery, countParams);

      return {
        devices: result.rows,
        total: parseInt(countResult.rows[0].count),
        filters
      };
    } finally {
      client.release();
    }
  }

  async lockDevice(deviceId, adminId, reason, ipAddress, lockLevel = 'soft') {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const deviceResult = await client.query(
        'SELECT * FROM devices WHERE id = $1',
        [deviceId]
      );

      if (deviceResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device not found' };
      }

      const device = deviceResult.rows[0];

      if (device.status === 'locked') {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device is already locked' };
      }

      if (device.status === 'decoupled') {
        await client.query('ROLLBACK');
        return { success: false, error: 'Cannot lock a decoupled device' };
      }

      const updateResult = await client.query(
        `UPDATE devices SET status = 'locked', lock_reason = $1, locked_by = $2, locked_at = NOW(), lock_level = $3, updated_at = NOW()
         WHERE id = $4 RETURNING *`,
        [reason, adminId, lockLevel, deviceId]
      );

      const firebaseService = require('../devices/firebaseService');
      await firebaseService.updateLockState(deviceId, 'locked', {
        reason,
        lockedBy: adminId,
        adminLock: true,
        lockLevel
      });

      const commandSigningService = require('../devices/commandSigningService');
      const signedCommand = await commandSigningService.createAndStoreSignedCommand(
        deviceId,
        'admin_lock',
        { reason, lockedBy: adminId, lockLevel },
        device.imei,
        { serial_number: device.serial_number, soc_id: device.soc_id }
      );

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'DEVICE_LOCKED_BY_ADMIN', 'device', $2, $3, $4, NOW())`,
        [adminId, deviceId, JSON.stringify({ deviceId, reason, lockLevel, lockedAt: new Date(), adminId }), ipAddress]
      );

      await client.query('COMMIT');

      logger.info(`Admin ${adminId} locked device ${deviceId}: ${reason} (${lockLevel})`);

      return {
        success: true,
        device: updateResult.rows[0],
        command: signedCommand
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to lock device:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async unlockDevice(deviceId, adminId, reason, ipAddress) {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const deviceResult = await client.query(
        'SELECT * FROM devices WHERE id = $1',
        [deviceId]
      );

      if (deviceResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device not found' };
      }

      const device = deviceResult.rows[0];

      if (device.status !== 'locked') {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device is not locked' };
      }

      const updateResult = await client.query(
        `UPDATE devices SET status = 'unlocked', lock_reason = NULL, locked_by = NULL, locked_at = NULL, lock_level = NULL, updated_at = NOW()
         WHERE id = $1 RETURNING *`,
        [deviceId]
      );

      const firebaseService = require('../devices/firebaseService');
      await firebaseService.updateLockState(deviceId, 'unlocked', {
        reason,
        unlockedBy: adminId,
        adminUnlock: true
      });

      const commandSigningService = require('../devices/commandSigningService');
      const signedCommand = await commandSigningService.createAndStoreSignedCommand(
        deviceId,
        'admin_unlock',
        { reason, unlockedBy: adminId },
        device.imei,
        { serial_number: device.serial_number, soc_id: device.soc_id }
      );

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'DEVICE_UNLOCKED_BY_ADMIN', 'device', $2, $3, $4, NOW())`,
        [adminId, deviceId, JSON.stringify({ deviceId, reason, unlockedAt: new Date(), adminId }), ipAddress]
      );

      await client.query('COMMIT');

      logger.info(`Admin ${adminId} unlocked device ${deviceId}: ${reason}`);

      return {
        success: true,
        device: updateResult.rows[0],
        command: signedCommand
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to unlock device:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async getAuditLog(filters = {}) {
    const client = await db.connect();
    try {
      let query = `
        SELECT al.*,
          u.name as actor_name, u.email as actor_email, u.role as actor_role
        FROM audit_log al
        LEFT JOIN users u ON al.actor = u.id::text
        WHERE 1=1
      `;

      const params = [];
      let paramCount = 0;

      if (filters.actor) {
        paramCount++;
        query += ` AND al.actor = $${paramCount}`;
        params.push(filters.actor);
      }

      if (filters.action) {
        paramCount++;
        query += ` AND al.action ILIKE $${paramCount}`;
        params.push(`%${filters.action}%`);
      }

      if (filters.targetType) {
        paramCount++;
        query += ` AND al.target_type = $${paramCount}`;
        params.push(filters.targetType);
      }

      if (filters.targetId) {
        paramCount++;
        query += ` AND al.target_id = $${paramCount}`;
        params.push(filters.targetId);
      }

      if (filters.ipAddress) {
        paramCount++;
        query += ` AND al.ip_address = $${paramCount}`;
        params.push(filters.ipAddress);
      }

      if (filters.startDate) {
        paramCount++;
        query += ` AND al.created_at >= $${paramCount}`;
        params.push(filters.startDate);
      }

      if (filters.endDate) {
        paramCount++;
        query += ` AND al.created_at <= $${paramCount}`;
        params.push(filters.endDate);
      }

      query += ' ORDER BY al.created_at DESC';

      const limit = filters.limit || 100;
      const offset = filters.offset || 0;

      paramCount++;
      query += ` LIMIT $${paramCount}`;
      params.push(limit);

      paramCount++;
      query += ` OFFSET $${paramCount}`;
      params.push(offset);

      const result = await client.query(query, params);

      let countQuery = `SELECT COUNT(*) FROM audit_log al WHERE 1=1`;
      const countParams = [];
      let countParamCount = 0;

      if (filters.actor) {
        countParamCount++;
        countQuery += ` AND al.actor = $${countParamCount}`;
        countParams.push(filters.actor);
      }

      if (filters.action) {
        countParamCount++;
        countQuery += ` AND al.action ILIKE $${countParamCount}`;
        countParams.push(`%${filters.action}%`);
      }

      if (filters.targetType) {
        countParamCount++;
        countQuery += ` AND al.target_type = $${countParamCount}`;
        countParams.push(filters.targetType);
      }

      if (filters.targetId) {
        countParamCount++;
        countQuery += ` AND al.target_id = $${countParamCount}`;
        countParams.push(filters.targetId);
      }

      if (filters.ipAddress) {
        countParamCount++;
        countQuery += ` AND al.ip_address = $${countParamCount}`;
        countParams.push(filters.ipAddress);
      }

      if (filters.startDate) {
        countParamCount++;
        countQuery += ` AND al.created_at >= $${countParamCount}`;
        countParams.push(filters.startDate);
      }

      if (filters.endDate) {
        countParamCount++;
        countQuery += ` AND al.created_at <= $${countParamCount}`;
        countParams.push(filters.endDate);
      }

      const countResult = await client.query(countQuery, countParams);

      return {
        entries: result.rows,
        total: parseInt(countResult.rows[0].count),
        limit,
        offset
      };
    } finally {
      client.release();
    }
  }

  async getSecurityEvents(filters = {}) {
    const client = await db.connect();
    try {
      let query = `
        SELECT se.*,
          u.name as actor_name, u.email as actor_email
        FROM security_events se
        LEFT JOIN users u ON se.actor = u.id::text
        WHERE 1=1
      `;

      const params = [];
      let paramCount = 0;

      if (filters.severity) {
        paramCount++;
        query += ` AND se.severity = $${paramCount}`;
        params.push(filters.severity);
      }

      if (filters.eventType) {
        paramCount++;
        query += ` AND se.event_type ILIKE $${paramCount}`;
        params.push(`%${filters.eventType}%`);
      }

      if (filters.startDate) {
        paramCount++;
        query += ` AND se.created_at >= $${paramCount}`;
        params.push(filters.startDate);
      }

      if (filters.endDate) {
        paramCount++;
        query += ` AND se.created_at <= $${paramCount}`;
        params.push(filters.endDate);
      }

      query += ' ORDER BY se.created_at DESC';

      const limit = filters.limit || 100;
      const offset = filters.offset || 0;

      paramCount++;
      query += ` LIMIT $${paramCount}`;
      params.push(limit);

      paramCount++;
      query += ` OFFSET $${paramCount}`;
      params.push(offset);

      const result = await client.query(query, params);

      let countQuery = `SELECT COUNT(*) FROM security_events se WHERE 1=1`;
      const countParams = [];
      let countParamCount = 0;

      if (filters.severity) {
        countParamCount++;
        countQuery += ` AND se.severity = $${countParamCount}`;
        countParams.push(filters.severity);
      }

      if (filters.eventType) {
        countParamCount++;
        countQuery += ` AND se.event_type ILIKE $${countParamCount}`;
        countParams.push(`%${filters.eventType}%`);
      }

      if (filters.startDate) {
        countParamCount++;
        countQuery += ` AND se.created_at >= $${countParamCount}`;
        countParams.push(filters.startDate);
      }

      if (filters.endDate) {
        countParamCount++;
        countQuery += ` AND se.created_at <= $${countParamCount}`;
        countParams.push(filters.endDate);
      }

      const countResult = await client.query(countQuery, countParams);

      return {
        events: result.rows,
        total: parseInt(countResult.rows[0].count),
        limit,
        offset
      };
    } finally {
      client.release();
    }
  }

  async addToNeirQueue(deviceId, adminId, reason, ipAddress) {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const deviceResult = await client.query(
        'SELECT imei, model, brand FROM devices WHERE id = $1',
        [deviceId]
      );

      if (deviceResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device not found' };
      }

      const device = deviceResult.rows[0];

      const existingResult = await client.query(
        "SELECT id FROM neir_queue WHERE device_id = $1 AND status = 'pending'",
        [deviceId]
      );

      if (existingResult.rows.length > 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Device is already in NEIR queue' };
      }

      const result = await client.query(
        `INSERT INTO neir_queue (device_id, imei, model, brand, reason, reported_by, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, 'pending', NOW())
         RETURNING *`,
        [deviceId, device.imei, device.model, device.brand, reason, adminId]
      );

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'DEVICE_ADDED_TO_NEIR_QUEUE', 'device', $2, $3, $4, NOW())`,
        [adminId, deviceId, JSON.stringify({ deviceId, imei: device.imei, reason }), ipAddress]
      );

      await client.query('COMMIT');

      logger.info(`Admin ${adminId} added device ${deviceId} to NEIR queue`);

      return {
        success: true,
        entry: result.rows[0]
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to add device to NEIR queue:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async getKeyRequests(filters = {}) {
    const client = await db.connect();
    try {
      let query = `
        SELECT kr.*,
          r.name as reseller_name, r.email as reseller_email, r.monthly_key_quota,
          u.name as approved_by_name
        FROM key_requests kr
        JOIN resellers r ON kr.reseller_id = r.id
        LEFT JOIN users u ON kr.approved_by = u.id
        WHERE 1=1
      `;

      const params = [];
      let paramCount = 0;

      if (filters.status) {
        paramCount++;
        query += ` AND kr.status = $${paramCount}`;
        params.push(filters.status);
      }

      if (filters.resellerId) {
        paramCount++;
        query += ` AND kr.reseller_id = $${paramCount}`;
        params.push(filters.resellerId);
      }

      query += ' ORDER BY kr.created_at DESC';

      const limit = filters.limit || 100;
      const offset = filters.offset || 0;

      paramCount++;
      query += ` LIMIT $${paramCount}`;
      params.push(limit);

      paramCount++;
      query += ` OFFSET $${paramCount}`;
      params.push(offset);

      const result = await client.query(query, params);

      let countQuery = `SELECT COUNT(*) FROM key_requests kr WHERE 1=1`;
      const countParams = [];
      let countParamCount = 0;

      if (filters.status) {
        countParamCount++;
        countQuery += ` AND kr.status = $${countParamCount}`;
        countParams.push(filters.status);
      }

      if (filters.resellerId) {
        countParamCount++;
        countQuery += ` AND kr.reseller_id = $${countParamCount}`;
        countParams.push(filters.resellerId);
      }

      const countResult = await client.query(countQuery, countParams);

      return {
        requests: result.rows,
        total: parseInt(countResult.rows[0].count),
        limit,
        offset
      };
    } finally {
      client.release();
    }
  }

  async rejectKeyRequest(requestId, rejectionReason, adminId, ipAddress) {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const requestResult = await client.query(
        'SELECT * FROM key_requests WHERE id = $1 AND status = $2',
        [requestId, 'pending']
      );

      if (requestResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Key request not found or not pending' };
      }

      const request = requestResult.rows[0];

      await client.query(
        `UPDATE key_requests
         SET status = 'rejected', rejection_reason = $1, rejected_by = $2, rejected_at = NOW(), updated_at = NOW()
         WHERE id = $3`,
        [rejectionReason, adminId, requestId]
      );

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'KEY_REQUEST_REJECTED', 'key_request', $2, $3, $4, NOW())`,
        [adminId, requestId, JSON.stringify({ requestId, rejectionReason, rejectedAt: new Date() }), ipAddress]
      );

      await client.query('COMMIT');

      logger.info(`Admin ${adminId} rejected key request ${requestId}: ${rejectionReason}`);

      return {
        success: true,
        requestId,
        rejectedAt: new Date()
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to reject key request:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  async approveKeyRequest(requestId, approvedQuantity, adminId, ipAddress) {
    const client = await db.connect();
    try {
      await client.query('BEGIN');

      const requestResult = await client.query(
        'SELECT * FROM key_requests WHERE id = $1 AND status = $2',
        [requestId, 'pending']
      );

      if (requestResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Key request not found or not pending' };
      }

      const request = requestResult.rows[0];

      const resellerResult = await client.query(
        'SELECT monthly_key_quota FROM resellers WHERE id = $1',
        [request.reseller_id]
      );

      if (resellerResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Reseller not found' };
      }

      const monthlyQuota = resellerResult.rows[0].monthly_key_quota;

      const approvedThisMonthResult = await client.query(
        `SELECT COUNT(*) FROM keys
         WHERE reseller_id = $1 AND created_at > NOW() - INTERVAL '30 days'`,
        [request.reseller_id]
      );
      const approvedThisMonth = parseInt(approvedThisMonthResult.rows[0].count);

      const maxAllowed = Math.max(0, Math.floor(monthlyQuota * 0.2) - approvedThisMonth);

      if (approvedQuantity > maxAllowed) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: `Approval quantity exceeds 20% of monthly quota (max: ${maxAllowed}, already approved: ${approvedThisMonth})`
        };
      }

      await client.query(
        `UPDATE key_requests
         SET status = 'approved', approved_quantity = $1, approved_by = $2, approved_at = NOW(), updated_at = NOW()
         WHERE id = $3`,
        [approvedQuantity, adminId, requestId]
      );

      const keyService = require('../keys/keyService');
      const generatedKeys = [];
      for (let i = 0; i < approvedQuantity; i++) {
        const keyString = await keyService.generateKeyString();
        generatedKeys.push(keyString);
      }

      for (const keyString of generatedKeys) {
        const { signature, timestamp } = keyService.signKey(keyString, request.reseller_id, Date.now().toString());
        await client.query(
          `INSERT INTO keys (key_string, reseller_id, status, signature, signature_timestamp, created_at)
           VALUES ($1, $2, 'approved', $3, $4, NOW())`,
          [keyString, request.reseller_id, signature, timestamp]
        );
      }

      await client.query(
        `INSERT INTO audit_log (actor, action, target_type, target_id, metadata, ip_address, created_at)
         VALUES ($1, 'KEY_REQUEST_APPROVED', 'key_request', $2, $3, $4, NOW())`,
        [adminId, requestId, JSON.stringify({ requestId, approvedQuantity, keyCount: generatedKeys.length }), ipAddress]
      );

      await client.query('COMMIT');

      logger.info(`Admin ${adminId} approved key request ${requestId} with ${approvedQuantity} keys`);

      return {
        success: true,
        requestId,
        approvedQuantity,
        generatedKeys
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to approve key request:', error);
      throw error;
    } finally {
      client.release();
    }
  }
}

module.exports = new AdminDeviceService();