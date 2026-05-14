const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const db = require('../../config/database');
const { createAuditLog } = require('../../utils/audit');
const { emitKeyRequested } = require('../sse/sseService');
const {
  generateKeyString,
  signKey,
  verifyKeySignature,
  isValidKeyFormat
} = require('./keyService');
const { sendCriticalAlertSMS } = require('../notifications/sms.service');

const KEY_STATUSES = {
  AVAILABLE: 'available',
  ASSIGNED: 'assigned',
  ACTIVATED: 'activated',
  REVOKED: 'revoked'
};

function normalizeQuantity(quantity) {
  const parsed = Number(quantity);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function hashImei(imei) {
  return crypto.createHash('sha256').update(String(imei)).digest('hex');
}

async function requestKeys(req, res) {
  try {
    const quantity = normalizeQuantity(req.body.quantity);
    const { justification } = req.body;
    const tier = ['standard', 'premium', 'vip'].includes(req.body.tier)
      ? req.body.tier
      : 'standard';
    const resellerId = req.user.id;

    if (!quantity || !justification) {
      return res.status(400).json({ error: 'Quantity and justification are required' });
    }

    const resellerResult = await db.query(
      `SELECT COALESCE(monthly_key_quota, monthly_quota, 100) as monthly_quota,
              COALESCE(used_keys, 0) as used_keys
       FROM resellers
       WHERE id = $1`,
      [resellerId]
    );

    if (resellerResult.rows.length === 0) {
      return res.status(404).json({ error: 'Reseller not found' });
    }

    const monthlyQuota = Number(resellerResult.rows[0].monthly_quota || 100);
    const maxPerRequest = Math.max(1, Math.floor(monthlyQuota * 0.2));

    if (quantity > maxPerRequest) {
      return res.status(400).json({
        error: `Cannot request more than 20% of monthly quota (${maxPerRequest}) in a single request`
      });
    }

    const requestResult = await db.query(
      `INSERT INTO key_requests (reseller_id, quantity, justification, tier, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, 'pending', NOW(), NOW())
       RETURNING id, quantity, tier, status, created_at`,
      [resellerId, quantity, justification, tier]
    );

    await createAuditLog(resellerId, 'KEY_REQUEST', {
      requestId: requestResult.rows[0].id,
      quantity,
      justification
    });

    // Notify all connected admins via SSE
    const resellerRow = await db.query('SELECT name FROM resellers WHERE id = $1', [resellerId]);
    emitKeyRequested(
      resellerId,
      resellerRow.rows[0]?.name || 'Reseller',
      requestResult.rows[0].id,
      quantity,
      tier
    );

    return res.status(201).json({
      message: 'Key request submitted',
      request: requestResult.rows[0]
    });
  } catch (error) {
    console.error('Request keys error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function approveKeyRequest(req, res) {
  const client = await db.getClient();

  try {
    const { requestId } = req.params;
    const adminId = req.user.id;

    await client.query('BEGIN');

    const requestResult = await client.query(
      `SELECT kr.*, COALESCE(r.monthly_key_quota, r.monthly_quota, 100) as monthly_quota
       FROM key_requests kr
       JOIN resellers r ON kr.reseller_id = r.id
       WHERE kr.id = $1
       FOR UPDATE`,
      [requestId]
    );

    if (requestResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Key request not found' });
    }

    const request = requestResult.rows[0];

    if (request.status !== 'pending') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Request already processed' });
    }

    const approvedQuantity = normalizeQuantity(
      req.body.approvedQuantity || req.body.quantity || request.quantity
    );
    if (!approvedQuantity || approvedQuantity > request.quantity) {
      await client.query('ROLLBACK');
      return res
        .status(400)
        .json({
          error: 'Approved quantity must be a positive number not greater than requested quantity'
        });
    }

    const approvedThisMonthResult = await client.query(
      `SELECT COUNT(*) FROM activation_keys
       WHERE reseller_id = $1 AND created_at > NOW() - INTERVAL '30 days'`,
      [request.reseller_id]
    );
    const approvedThisMonth = parseInt(approvedThisMonthResult.rows[0].count, 10);
    const maxAllowed = Math.max(
      0,
      Math.floor(Number(request.monthly_quota || 100) * 0.2) - approvedThisMonth
    );

    if (approvedQuantity > maxAllowed) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Approval quantity exceeds 20% of monthly quota (max: ${maxAllowed}, already approved: ${approvedThisMonth})`
      });
    }

    const generatedKeys = [];
    for (let i = 0; i < approvedQuantity; i++) {
      const keyString = await generateKeyString(client);
      const nonce = crypto.randomBytes(16).toString('hex');
      const { signature, timestamp } = signKey(keyString, request.reseller_id, nonce);

      const keyResult = await client.query(
        `INSERT INTO activation_keys (
          key_string, reseller_id, request_id, hmac_signature, nonce,
          sig_timestamp, status, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        RETURNING id, key_string`,
        [
          keyString,
          request.reseller_id,
          request.id,
          signature,
          nonce,
          timestamp,
          KEY_STATUSES.AVAILABLE
        ]
      );

      generatedKeys.push(keyResult.rows[0]);
    }

    await client.query(
      `UPDATE key_requests
       SET status = 'approved', approved_quantity = $1, approved_by = $2, approved_at = NOW(), updated_at = NOW()
       WHERE id = $3`,
      [approvedQuantity, adminId, requestId]
    );

    await client.query(
      `UPDATE resellers
       SET used_keys = COALESCE(used_keys, 0) + $1, updated_at = NOW()
       WHERE id = $2`,
      [approvedQuantity, request.reseller_id]
    );

    await client.query('COMMIT');

    await createAuditLog(adminId, 'KEYS_APPROVED', {
      requestId,
      quantity: approvedQuantity,
      resellerId: request.reseller_id
    });

    return res.json({
      message: 'Keys generated and assigned to reseller inventory',
      keys: generatedKeys.map((k) => ({ id: k.id, key: k.key_string }))
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Approve key request error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
}

async function rejectKeyRequest(req, res) {
  try {
    const { requestId } = req.params;
    const { rejectionReason, rejection_reason: rejectionReasonLegacy } = req.body;
    const reason = rejectionReason || rejectionReasonLegacy;
    const adminId = req.user.id;

    if (!reason) {
      return res.status(400).json({ error: 'Rejection reason is required' });
    }

    const result = await db.query(
      `UPDATE key_requests
       SET status = 'rejected', rejected_by = $1, rejected_at = NOW(),
           rejection_reason = $2, updated_at = NOW()
       WHERE id = $3 AND status = 'pending'
       RETURNING id, quantity, reseller_id`,
      [adminId, reason, requestId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Key request not found or not pending' });
    }

    await createAuditLog(adminId, 'KEYS_REJECTED', {
      requestId,
      resellerId: result.rows[0].reseller_id,
      rejectionReason: reason
    });

    return res.json({ message: 'Key request rejected', requestId });
  } catch (error) {
    console.error('Reject key request error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function assignKeys(req, res) {
  const client = await db.getClient();

  try {
    const quantity = normalizeQuantity(req.body.quantity);
    const dealerId = req.body.dealerId || req.body.dealer_id;
    const resellerId = req.user.id;
    const tier = ['standard', 'premium', 'vip'].includes(req.body.tier)
      ? req.body.tier
      : 'standard';

    if (!quantity || !dealerId) {
      return res.status(400).json({ error: 'Quantity and dealerId are required' });
    }

    await client.query('BEGIN');

    const dealerResult = await client.query(
      `SELECT id, user_id FROM dealers
       WHERE (id = $1 OR user_id = $1) AND reseller_id = $2`,
      [dealerId, resellerId]
    );

    if (dealerResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Dealer not found or not authorized' });
    }

    const targetDealerId = dealerResult.rows[0].user_id || dealerResult.rows[0].id;

    // On-demand model: check reseller quota, generate fresh keys, decrement quota.
    const quotaCol = `quota_${tier}`;
    const quotaResult = await client.query(
      `SELECT COALESCE(${quotaCol}, 0) AS available FROM resellers WHERE id = $1 FOR UPDATE`,
      [resellerId]
    );
    const available = parseInt(quotaResult.rows[0]?.available ?? '0', 10);

    if (available < quantity) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Only ${available} ${tier} keys available for assignment`
      });
    }

    // Generate fresh keys and assign directly to dealer.
    const keyIds = [];
    for (let i = 0; i < quantity; i++) {
      const keyString = await generateKeyString(client);
      const nonce = crypto.randomBytes(16).toString('hex');
      const { signature, timestamp } = signKey(keyString, targetDealerId, nonce);

      const insertResult = await client.query(
        `INSERT INTO activation_keys
           (key_string, reseller_id, dealer_id, status, tier, hmac_signature, nonce, sig_timestamp, assigned_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW(), NOW())
         RETURNING id`,
        [
          keyString,
          resellerId,
          targetDealerId,
          KEY_STATUSES.ASSIGNED,
          tier,
          signature,
          nonce,
          timestamp
        ]
      );
      keyIds.push(insertResult.rows[0].id);
    }

    // Decrement reseller quota.
    await client.query(
      `UPDATE resellers SET ${quotaCol} = ${quotaCol} - $1, updated_at = NOW() WHERE id = $2`,
      [quantity, resellerId]
    );

    // Create credit ledger entry.
    await client.query(
      `INSERT INTO dealer_credit_ledger
         (reseller_id, dealer_id, keys_quantity, tier, created_at, updated_at)
       VALUES ($1, $2, $3, $4, NOW(), NOW())`,
      [resellerId, targetDealerId, quantity, tier]
    );

    await client.query('COMMIT');

    await createAuditLog(resellerId, 'KEYS_ASSIGNED', {
      resellerId,
      dealerId: targetDealerId,
      quantity,
      tier,
      keyIds
    });

    return res.json({
      message: `${quantity} ${tier} keys assigned to dealer`,
      assignedCount: quantity
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Assign keys error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
}

async function consumeKey(req, res) {
  const client = await db.getClient();

  try {
    const {
      keyString,
      imei,
      fcmToken = null,
      serialNumber = null,
      socId = null,
      deviceName = null,
      model = null,
      brand = null
    } = req.body;
    const dealerId = req.user.id;

    if (!keyString || !imei) {
      return res.status(400).json({ error: 'Key and IMEI are required' });
    }

    if (!isValidKeyFormat(keyString)) {
      return res.status(400).json({ error: 'Invalid key format' });
    }

    if (!/^[0-9]{14,17}$/.test(String(imei))) {
      return res.status(400).json({ error: 'Invalid IMEI format' });
    }

    await client.query('BEGIN');

    const keyResult = await client.query(
      `SELECT * FROM activation_keys
       WHERE key_string = $1 AND dealer_id = $2
       FOR UPDATE`,
      [keyString, dealerId]
    );

    if (keyResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Key not found or not assigned to this dealer' });
    }

    const key = keyResult.rows[0];
    if (key.status === KEY_STATUSES.ACTIVATED) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Key already used' });
    }

    if (key.status !== KEY_STATUSES.ASSIGNED) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Key is not available for activation' });
    }

    if (
      !verifyKeySignature(
        key.key_string,
        dealerId,
        key.sig_timestamp,
        key.nonce,
        key.hmac_signature
      )
    ) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Key cryptographic signature validation failed' });
    }

    const deviceId = uuidv4();
    const imeiHash = hashImei(imei);

    await client.query(
      `INSERT INTO devices (
        id, imei, imei_hash, serial_number, soc_id, dealer_id, reseller_id,
        activation_key_id, fcm_token, device_name, model, brand, status,
        lock_level, created_at, updated_at, enrolled_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'enrolled', 'NONE', NOW(), NOW(), NOW())
      RETURNING id`,
      [
        deviceId,
        imei,
        imeiHash,
        serialNumber,
        socId,
        dealerId,
        key.reseller_id,
        key.id,
        fcmToken,
        deviceName,
        model,
        brand
      ]
    );

    await client.query(
      `UPDATE activation_keys
       SET status = $1, imei_hash = $2, device_id = $3, activated_at = NOW(), updated_at = NOW()
       WHERE id = $4`,
      [KEY_STATUSES.ACTIVATED, imeiHash, deviceId, key.id]
    );

    const velocityCheck = await client.query(
      `SELECT COUNT(*) as count FROM activation_keys
       WHERE dealer_id = $1 AND activated_at > NOW() - INTERVAL '24 hours'`,
      [dealerId]
    );

    await client.query('COMMIT');

    const keysUsed24h = parseInt(velocityCheck.rows[0].count, 10);
    if (keysUsed24h >= 10) {
      await createAuditLog(dealerId, 'VELOCITY_ALERT', {
        dealerId,
        keysUsed24h,
        alert: 'Dealer using 10+ keys in 24 hours'
      });

      const adminPhone = process.env.ADMIN_VELOCITY_ALERT_PHONE;
      if (adminPhone) {
        await sendCriticalAlertSMS(
          adminPhone,
          `VELOCITY_ALERT: Dealer ${dealerId} has activated ${keysUsed24h} keys in 24 hours. Threshold: 10.`
        );
      }
    }

    await createAuditLog(dealerId, 'KEY_CONSUMED', {
      keyId: key.id,
      dealerId,
      deviceId,
      imeiHash,
      timestamp: new Date()
    });

    return res.json({
      message: 'Key consumed successfully',
      deviceId,
      imei,
      consumedAt: new Date()
    });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Consume key error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
}

async function getDealerKeys(req, res) {
  try {
    const { status } = req.query;
    const params = [req.user.id];
    let where = 'dealer_id = $1';

    if (status) {
      params.push(String(status).toLowerCase());
      where += ` AND status = $${params.length}`;
    }

    const result = await db.query(
      `SELECT id, key_string, status, assigned_at, activated_at, created_at
       FROM activation_keys
       WHERE ${where}
       ORDER BY created_at DESC`,
      params
    );

    return res.json({ keys: result.rows, total: result.rows.length });
  } catch (error) {
    console.error('Get dealer keys error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function getResellerKeys(req, res) {
  try {
    const { status } = req.query;
    const params = [req.user.id];
    let where = 'ak.reseller_id = $1';

    if (status) {
      params.push(String(status).toLowerCase());
      where += ` AND ak.status = $${params.length}`;
    }

    const result = await db.query(
      `SELECT ak.id, ak.key_string, ak.status, ak.tier, ak.dealer_id, d.name as dealer_name,
              ak.assigned_at, ak.activated_at, ak.created_at
       FROM activation_keys ak
       LEFT JOIN dealers d ON ak.dealer_id = d.user_id OR ak.dealer_id = d.id
       WHERE ${where}
       ORDER BY ak.created_at DESC`,
      params
    );

    return res.json({ keys: result.rows, total: result.rows.length });
  } catch (error) {
    console.error('Get reseller keys error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

async function getDealerInventory(req, res) {
  try {
    const dealerId = req.user.id;

    // Count keys by tier and status
    const keysResult = await db.query(
      `SELECT tier,
              COUNT(*) FILTER (WHERE status = 'assigned')  AS assigned,
              COUNT(*) FILTER (WHERE status = 'activated') AS activated,
              COUNT(*) FILTER (WHERE status = 'revoked')   AS revoked
       FROM activation_keys
       WHERE dealer_id = $1
       GROUP BY tier`,
      [dealerId]
    );

    // Get dealer quotas
    const dealerResult = await db.query(
      `SELECT quota_standard, quota_premium, quota_vip
       FROM dealers WHERE user_id = $1`,
      [dealerId]
    );

    const quotas = dealerResult.rows[0] || {
      quota_standard: 500,
      quota_premium: 200,
      quota_vip: 50
    };
    const byTier = { standard: {}, premium: {}, vip: {} };

    for (const row of keysResult.rows) {
      byTier[row.tier] = {
        assigned: parseInt(row.assigned, 10),
        activated: parseInt(row.activated, 10),
        revoked: parseInt(row.revoked, 10)
      };
    }

    return res.json({
      standard: {
        assigned: 0,
        activated: 0,
        revoked: 0,
        quota: quotas.quota_standard,
        ...byTier.standard
      },
      premium: {
        assigned: 0,
        activated: 0,
        revoked: 0,
        quota: quotas.quota_premium,
        ...byTier.premium
      },
      vip: { assigned: 0, activated: 0, revoked: 0, quota: quotas.quota_vip, ...byTier.vip }
    });
  } catch (error) {
    console.error('Get dealer inventory error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

module.exports = {
  requestKeys,
  approveKeyRequest,
  rejectKeyRequest,
  assignKeys,
  consumeKey,
  getDealerKeys,
  getResellerKeys,
  getDealerInventory
};
