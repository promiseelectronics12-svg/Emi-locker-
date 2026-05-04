const db = require('../../config/database');
const crypto = require('crypto');
const { createAuditLog } = require('../../utils/audit');
const { generateKeyString, signKey, verifyKeySignature } = require('./keyService');
const { sendCriticalAlertSMS } = require('../notifications/sms.service');

async function requestKeys(req, res) {
  try {
    const { quantity, justification } = req.body;
    const resellerId = req.user.id;

    if (!quantity || !justification) {
      return res.status(400).json({ error: 'Quantity and justification are required' });
    }

    if (quantity <= 0 || !Number.isInteger(quantity)) {
      return res.status(400).json({ error: 'Quantity must be a positive integer' });
    }

    const resellerResult = await db.query(
      'SELECT monthly_quota, used_keys FROM resellers WHERE id = $1',
      [resellerId]
    );

    if (resellerResult.rows.length === 0) {
      return res.status(404).json({ error: 'Reseller not found' });
    }

    const { monthly_quota } = resellerResult.rows[0];
    const maxPerRequest = Math.floor(monthly_quota * 0.2);

    if (quantity > maxPerRequest) {
      return res.status(400).json({
        error: `Cannot request more than 20% of monthly quota (${maxPerRequest}) in a single request`
      });
    }

    const requestResult = await db.query(
      `INSERT INTO key_requests (reseller_id, quantity, justification, status, created_at)
       VALUES ($1, $2, $3, 'PENDING_ADMIN', NOW())
       RETURNING id, quantity, status, created_at`,
      [resellerId, quantity, justification]
    );

    await createAuditLog(resellerId, 'KEY_REQUEST', {
      requestId: requestResult.rows[0].id,
      quantity,
      justification
    });

    res.status(201).json({
      message: 'Key request submitted',
      request: requestResult.rows[0]
    });
  } catch (error) {
    console.error('Request keys error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function approveKeyRequest(req, res) {
  try {
    const { requestId } = req.params;
    const adminId = req.user.id;

    const requestResult = await db.query(
      `SELECT kr.*, r.monthly_quota, r.used_keys, r.id as reseller_id
       FROM key_requests kr
       JOIN resellers r ON kr.reseller_id = r.id
       WHERE kr.id = $1`,
      [requestId]
    );

    if (requestResult.rows.length === 0) {
      return res.status(404).json({ error: 'Key request not found' });
    }

    const request = requestResult.rows[0];

    if (request.status !== 'PENDING_ADMIN') {
      return res.status(400).json({ error: 'Request already processed' });
    }

    const generatedKeys = [];
    const timestamp = Date.now();

    const client = await db.getClient();
    await client.query('BEGIN');

    try {
      for (let i = 0; i < request.quantity; i++) {
        const keyString = await generateKeyString();
        const nonce = crypto.randomBytes(16).toString('hex');
        const { signature } = signKey(keyString, request.reseller_id, nonce);

        const keyResult = await client.query(
          `INSERT INTO keys (key_string, dealer_id, reseller_id, hmac_signature, timestamp, nonce, status, created_at, expires_at)
           VALUES ($1, NULL, $2, $3, $4, $5, 'GENERATED', NOW(), NOW() + INTERVAL '72 hours')
           RETURNING id, key_string, hmac_signature`,
          [keyString, request.reseller_id, signature, timestamp, nonce]
        );

        generatedKeys.push(keyResult.rows[0]);
      }

      await client.query(
        `UPDATE key_requests SET status = 'APPROVED', approved_by = $1, approved_at = NOW() WHERE id = $2`,
        [adminId, requestId]
      );

      await client.query(
        'UPDATE resellers SET used_keys = used_keys + $1 WHERE id = $2',
        [request.quantity, request.reseller_id]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    await createAuditLog(adminId, 'KEYS_APPROVED', {
      requestId,
      quantity: request.quantity,
      resellerId: request.reseller_id
    });

    res.json({
      message: 'Keys generated and assigned to reseller',
      keys: generatedKeys.map(k => ({
        id: k.id,
        key: k.key_string
      }))
    });
  } catch (error) {
    console.error('Approve key request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function rejectKeyRequest(req, res) {
  try {
    const { requestId } = req.params;
    const { rejection_reason } = req.body;
    const adminId = req.user.id;

    if (!rejection_reason) {
      return res.status(400).json({ error: 'Rejection reason is required' });
    }

    const requestResult = await db.query(
      `SELECT kr.* FROM key_requests kr WHERE kr.id = $1`,
      [requestId]
    );

    if (requestResult.rows.length === 0) {
      return res.status(404).json({ error: 'Key request not found' });
    }

    const request = requestResult.rows[0];

    if (request.status !== 'PENDING_ADMIN') {
      return res.status(400).json({ error: 'Request already processed' });
    }

    await db.query(
      `UPDATE key_requests SET status = 'REJECTED', rejected_by = $1, rejected_at = NOW(), rejection_reason = $2 WHERE id = $3`,
      [adminId, rejection_reason, requestId]
    );

    await createAuditLog(adminId, 'KEYS_REJECTED', {
      requestId,
      quantity: request.quantity,
      resellerId: request.reseller_id,
      rejection_reason
    });

    res.json({
      message: 'Key request rejected',
      requestId
    });
  } catch (error) {
    console.error('Reject key request error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function assignKeys(req, res) {
  try {
    const { quantity, dealerId } = req.body;
    const resellerId = req.user.id;

    if (!quantity || !dealerId) {
      return res.status(400).json({ error: 'Quantity and dealerId are required' });
    }

    if (quantity <= 0 || !Number.isInteger(quantity)) {
      return res.status(400).json({ error: 'Quantity must be a positive integer' });
    }

    const dealerResult = await db.query(
      'SELECT id, reseller_id FROM dealers WHERE id = $1 AND reseller_id = $2',
      [dealerId, resellerId]
    );

    if (dealerResult.rows.length === 0) {
      return res.status(404).json({ error: 'Dealer not found or not authorized' });
    }

    const availableKeys = await db.query(
      `SELECT id, key_string FROM keys
       WHERE reseller_id = $1 AND dealer_id IS NULL AND status = 'GENERATED'
       ORDER BY created_at ASC
       LIMIT $2 FOR UPDATE SKIP LOCKED`,
      [resellerId, quantity]
    );

    if (availableKeys.rows.length < quantity) {
      return res.status(400).json({
        error: `Only ${availableKeys.rows.length} keys available for assignment`
      });
    }

    const client = await db.getClient();
    await client.query('BEGIN');

    try {
      const keyIds = [];
      for (const row of availableKeys.rows) {
        const nonce = crypto.randomBytes(16).toString('hex');
        const { signature, timestamp } = signKey(row.key_string, dealerId, nonce);
        
        await client.query(
          `UPDATE keys SET dealer_id = $1, status = 'ASSIGNED', assigned_at = NOW(), hmac_signature = $2, nonce = $3, timestamp = $4 WHERE id = $5`,
          [dealerId, signature, nonce, timestamp, row.id]
        );
        keyIds.push(row.id);
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    await createAuditLog(resellerId, 'KEYS_ASSIGNED', {
      resellerId,
      dealerId,
      quantity,
      keyIds
    });

    res.json({
      message: `${quantity} keys assigned to dealer`,
      assignedCount: quantity
    });
  } catch (error) {
    console.error('Assign keys error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

async function consumeKey(req, res) {
  try {
    const { keyString, imei } = req.body;
    const dealerId = req.user.id;

    if (!keyString || !imei) {
      return res.status(400).json({ error: 'Key and IMEI are required' });
    }

    if (!/^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(keyString)) {
      return res.status(400).json({ error: 'Invalid key format' });
    }

    if (!/^[0-9]{15}$/.test(imei)) {
      return res.status(400).json({ error: 'Invalid IMEI format' });
    }

    const client = await db.getClient();
    await client.query('BEGIN');

    try {
      const keyResult = await client.query(
        `SELECT k.* FROM keys k
         WHERE k.key_string = $1 AND k.dealer_id = $2 FOR UPDATE`,
        [keyString, dealerId]
      );

      if (keyResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Key not found or not assigned to this dealer' });
      }

      const key = keyResult.rows[0];

      if (!verifyKeySignature(key.key_string, dealerId, key.timestamp, key.nonce, key.hmac_signature)) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Key cryptographic signature validation failed. Key integrity compromised.' });
      }

      if (key.status === 'CONSUMED') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Key already used' });
      }

      if (key.status === 'EXPIRED') {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: 'Key has expired' });
      }

      if (new Date() > new Date(key.expires_at)) {
        await client.query('UPDATE keys SET status = $1 WHERE id = $2', ['EXPIRED', key.id]);
        await client.query('COMMIT');
        return res.status(400).json({ error: 'Key has expired' });
      }

      await client.query(
        `UPDATE keys SET status = 'CONSUMED', imei = $1, consumed_at = NOW() WHERE id = $2`,
        [imei, key.id]
      );

      const velocityCheck = await client.query(
        `SELECT COUNT(*) as count FROM keys
         WHERE dealer_id = $1 AND consumed_at > NOW() - INTERVAL '24 hours'`,
        [dealerId]
      );

      if (parseInt(velocityCheck.rows[0].count) >= 10) {
        await createAuditLog(dealerId, 'VELOCITY_ALERT', {
          dealerId,
          keysUsed24h: parseInt(velocityCheck.rows[0].count),
          alert: 'Dealer using 10+ keys in 24 hours'
        });

        const adminPhone = process.env.ADMIN_VELOCITY_ALERT_PHONE;
        if (adminPhone) {
          await sendCriticalAlertSMS(
            adminPhone,
            `VELOCITY_ALERT: Dealer ${dealerId} has consumed ${velocityCheck.rows[0].count} keys in 24 hours. Threshold: 10.`
          );
        }

        if (parseInt(velocityCheck.rows[0].count) >= 15) {
          console.error(`CRITICAL: Dealer ${dealerId} exceeded block threshold (15 keys/24h). Keys consumed: ${velocityCheck.rows[0].count}`);
        }
      }

      await createAuditLog(dealerId, 'KEY_CONSUMED', {
        keyId: key.id,
        dealerId,
        imei,
        timestamp: new Date()
      });

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    res.json({
      message: 'Key consumed successfully',
      imei,
      consumedAt: new Date()
    });
  } catch (error) {
    console.error('Consume key error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}

module.exports = {
  requestKeys,
  approveKeyRequest,
  rejectKeyRequest,
  assignKeys,
  consumeKey
};