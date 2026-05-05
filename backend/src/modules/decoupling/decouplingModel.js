const db = require('../../config/database');
const { v4: uuidv4 } = require('uuid');
const logger = require('../../utils/logger');

const DECOUPLING_STATES = {
  EMI_ACTIVE: 'EMI_ACTIVE',
  FINAL_PAYMENT_RECEIVED: 'FINAL_PAYMENT_RECEIVED',
  DEALER_NOTIFIED: 'DEALER_NOTIFIED',
  FRAUD_FLAGGED: 'FRAUD_FLAGGED',
  FRAUD_CONFIRMED: 'FRAUD_CONFIRMED',
  FRAUD_REJECTED: 'FRAUD_REJECTED',
  PENDING_ADMIN_DECOUPLE: 'PENDING_ADMIN_DECOUPLE',
  DEVICE_DECOUPLED: 'DEVICE_DECOUPLED',
};

// ============================================================
// Valid state transitions — the core of the state machine
// Dealer CANNOT block or delay decoupling.
// Dealer's only role during DEALER_NOTIFIED is to FLAG fraud.
// ============================================================
const VALID_TRANSITIONS = {
  [DECOUPLING_STATES.EMI_ACTIVE]: [
    DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED,
  ],
  [DECOUPLING_STATES.FINAL_PAYMENT_RECEIVED]: [
    DECOUPLING_STATES.DEALER_NOTIFIED,
  ],
  [DECOUPLING_STATES.DEALER_NOTIFIED]: [
    DECOUPLING_STATES.FRAUD_FLAGGED,         // dealer raises fraud flag
    DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, // 5-day window expires, no fraud
  ],
  [DECOUPLING_STATES.FRAUD_FLAGGED]: [
    DECOUPLING_STATES.FRAUD_CONFIRMED,        // admin confirms fraud
    DECOUPLING_STATES.FRAUD_REJECTED,         // admin rejects fraud → continues
  ],
  [DECOUPLING_STATES.FRAUD_REJECTED]: [
    DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE, // fraud rejected, proceed to admin
  ],
  [DECOUPLING_STATES.FRAUD_CONFIRMED]: [],    // terminal — decoupling blocked
  [DECOUPLING_STATES.PENDING_ADMIN_DECOUPLE]: [
    DECOUPLING_STATES.DEVICE_DECOUPLED,       // admin executes decoupling
  ],
  [DECOUPLING_STATES.DEVICE_DECOUPLED]: [],   // terminal — immutable
};

async function beginTransaction() {
  const client = await db.getClient();
  await client.query('BEGIN');
  return client;
}

async function commitTransaction(client) {
  await client.query('COMMIT');
  client.release();
}

async function rollbackTransaction(client) {
  await client.query('ROLLBACK');
  client.release();
}

class DecouplingModel {
  async create(deviceId, emiScheduleId) {
    const id = uuidv4();
    const result = await db.query(
      `INSERT INTO decoupling (id, device_id, emi_schedule_id, state, created_at, updated_at)
       VALUES ($1, $2, $3, $4, NOW(), NOW())
       RETURNING *`,
      [id, deviceId, emiScheduleId, DECOUPLING_STATES.EMI_ACTIVE]
    );
    return result.rows[0];
  }

  async getByDeviceId(deviceId) {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id,
              dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       LEFT JOIN dealers dl ON dev.dealer_id = dl.id
       WHERE d.device_id = $1`,
      [deviceId]
    );
    return result.rows[0] || null;
  }

  async getByDeviceIdInTransaction(client, deviceId) {
    const result = await client.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id,
              dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       LEFT JOIN dealers dl ON dev.dealer_id = dl.id
       WHERE d.device_id = $1`,
      [deviceId]
    );
    return result.rows[0] || null;
  }

  async getById(id) {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       WHERE d.id = $1`,
      [id]
    );
    return result.rows[0] || null;
  }

  async updateState(deviceId, newState, currentState, additionalData = {}, client = null) {
    const allowedColumns = [
      'dealer_notified_at', 'fraud_window_started_at', 'fraud_window_ends_at',
      'fraud_flag', 'fraud_flagged_by', 'fraud_flagged_at', 'fraud_reason', 'fraud_evidence_url',
      'fraud_confirmed_by', 'fraud_confirmed_at', 'fraud_rejected_by', 'fraud_rejected_at',
      'rtoc_code_hash', 'rtoc_generated_at', 'rtoc_generated_by',
      'admin_action_by', 'admin_action_at', 'admin_2fa_verified',
      'fcm_sent_at', 'fcm_delivered', 'fcm_failure_reason',
      'padt_token_id', 'padt_issued_at', 'padt_expires_at',
      'amapi_deleted_at', 'amapi_delete_success',
      'decoupled_at', 'decoupled_by',
      'auto_notify_admin_at',
    ];

    const setClauses = ['state = $1', 'updated_at = NOW()'];
    const values = [newState];
    let paramIndex = 2;

    for (const [key, value] of Object.entries(additionalData)) {
      if (allowedColumns.includes(key)) {
        setClauses.push(`${key} = $${paramIndex}`);
        values.push(value);
        paramIndex++;
      }
    }

    values.push(deviceId);
    values.push(currentState);
    const queryFn = client ? (text, vals) => client.query(text, vals) : db.query;
    const result = await queryFn(
      `UPDATE decoupling
       SET ${setClauses.join(', ')}
       WHERE device_id = $${paramIndex} AND state = $${paramIndex + 1}
       RETURNING *`,
      values
    );

    if (result.rowCount === 0) {
      throw new Error('Concurrent state transition detected — state may have changed');
    }
    return result.rows[0];
  }

  async setFraudWindow(deviceId) {
    const fraudWindowDays = process.env.DECOUPLING_FRAUD_WINDOW_DAYS || 5;
    const result = await db.query(
      `UPDATE decoupling
       SET fraud_window_started_at = NOW(),
           fraud_window_ends_at = NOW() + ($2 || ' days')::interval,
           auto_notify_admin_at = NOW() + ($2 || ' days')::interval,
           updated_at = NOW()
       WHERE device_id = $1
       RETURNING *`,
      [deviceId, fraudWindowDays]
    );
    return result.rows[0];
  }

  async flagFraud(deviceId, flaggedBy, reason, evidenceUrl) {
    const result = await db.query(
      `UPDATE decoupling
       SET fraud_flag = true,
           fraud_flagged_by = $1,
           fraud_flagged_at = NOW(),
           fraud_reason = $2,
           fraud_evidence_url = $3,
           state = $4,
           updated_at = NOW()
       WHERE device_id = $5
       RETURNING *`,
      [flaggedBy, reason, evidenceUrl, DECOUPLING_STATES.FRAUD_FLAGGED, deviceId]
    );
    return result.rows[0];
  }

  async confirmFraud(deviceId, confirmedBy) {
    const result = await db.query(
      `UPDATE decoupling
       SET fraud_confirmed_by = $1,
           fraud_confirmed_at = NOW(),
           state = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [confirmedBy, DECOUPLING_STATES.FRAUD_CONFIRMED, deviceId]
    );
    return result.rows[0];
  }

  async rejectFraud(deviceId, rejectedBy) {
    const result = await db.query(
      `UPDATE decoupling
       SET fraud_rejected_by = $1,
           fraud_rejected_at = NOW(),
           fraud_flag = false,
           state = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [rejectedBy, DECOUPLING_STATES.FRAUD_REJECTED, deviceId]
    );
    return result.rows[0];
  }

  async setRTOC(deviceId, rtocCodeHash, generatedBy, client = null) {
    const queryFn = client ? (text, vals) => client.query(text, vals) : db.query;
    const result = await queryFn(
      `UPDATE decoupling
       SET rtoc_code_hash = $1,
           rtoc_generated_at = NOW(),
           rtoc_generated_by = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [rtocCodeHash, generatedBy, deviceId]
    );
    return result.rows[0];
  }

  async setAdmin2FA(deviceId, adminId, client = null) {
    const queryFn = client ? (text, vals) => client.query(text, vals) : db.query;
    const result = await queryFn(
      `UPDATE decoupling
       SET admin_action_by = $1,
           admin_action_at = NOW(),
           admin_2fa_verified = true,
           updated_at = NOW()
       WHERE device_id = $2
       RETURNING *`,
      [adminId, deviceId]
    );
    return result.rows[0];
  }

  async markFCMSent(deviceId, success, failureReason, client = null) {
    const queryFn = client ? (text, vals) => client.query(text, vals) : db.query;
    const result = await queryFn(
      `UPDATE decoupling
       SET fcm_sent_at = NOW(),
           fcm_delivered = $1,
           fcm_failure_reason = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [success, failureReason, deviceId]
    );
    return result.rows[0];
  }

  async markPADTIssued(deviceId, tokenId, expiresAt) {
    const result = await db.query(
      `UPDATE decoupling
       SET padt_token_id = $1,
           padt_issued_at = NOW(),
           padt_expires_at = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [tokenId, expiresAt, deviceId]
    );
    return result.rows[0];
  }

  async markAMAPIDeleted(deviceId, success, client = null) {
    const status = success ? 'completed' : 'failed_retrying';
    const queryFn = client ? (text, vals) => client.query(text, vals) : db.query;
    const result = await queryFn(
      `UPDATE decoupling
       SET amapi_deleted_at = NOW(),
           amapi_delete_success = $1,
           amapi_deletion_status = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [success, status, deviceId]
    );
    return result.rows[0];
  }

  async updateAMAPIDeletionStatus(deviceId, status) {
    const result = await db.query(
      `UPDATE decoupling
       SET amapi_deletion_status = $1,
           updated_at = NOW()
       WHERE device_id = $2
       RETURNING *`,
      [status, deviceId]
    );
    return result.rows[0];
  }

  async getPendingAMAPIDeletions() {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.amapi_device_name
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       WHERE d.amapi_deletion_status IN ('pending', 'failed_retrying')
         AND d.state = 'DEVICE_DECOUPLED'`
    );
    return result.rows;
  }

  async markDecoupled(deviceId, decoupledBy) {
    const result = await db.query(
      `UPDATE decoupling
       SET decoupled_at = NOW(),
           decoupled_by = $1,
           state = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [decoupledBy, DECOUPLING_STATES.DEVICE_DECOUPLED, deviceId]
    );
    return result.rows[0];
  }

  async getDevicesInState(state) {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       WHERE d.state = $1`,
      [state]
    );
    return result.rows;
  }

  async getDevicesWithExpiredFraudWindow() {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       WHERE d.state = $1
         AND d.fraud_flag = false
         AND d.fraud_window_ends_at <= NOW()`,
      [DECOUPLING_STATES.DEALER_NOTIFIED]
    );
    return result.rows;
  }

  async getDevicesReadyForAdminNotification() {
    const result = await db.query(
      `SELECT d.*,
              dev.imei, dev.model, dev.brand, dev.fcm_token, dev.amapi_device_name,
              dev.dealer_id, dev.owner_id
       FROM decoupling d
       JOIN devices dev ON d.device_id = dev.id
       WHERE d.state = $1
         AND d.fraud_flag = false
         AND d.auto_notify_admin_at <= NOW()`,
      [DECOUPLING_STATES.DEALER_NOTIFIED]
    );
    return result.rows;
  }

  async createAuditLog(decouplingId, deviceId, fromState, toState, actorId, actorType, action, details = {}, ipAddress, userAgent) {
    const id = uuidv4();
    await db.query(
      `INSERT INTO decoupling_audit_log
       (id, decoupling_id, device_id, from_state, to_state, actor_id, actor_type, action, details_json, ip_address, user_agent, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())`,
      [id, decouplingId, deviceId, fromState, toState, actorId, actorType, action, JSON.stringify(details), ipAddress, userAgent]
    );
    return id;
  }

  async getAuditLogs(deviceId, limit = 50) {
    const result = await db.query(
      `SELECT dal.*, u.email as actor_email
       FROM decoupling_audit_log dal
       LEFT JOIN users u ON dal.actor_id = u.id
       WHERE dal.device_id = $1
       ORDER BY dal.created_at DESC
       LIMIT $2`,
      [deviceId, limit]
    );
    return result.rows;
  }

  async verifyFinalPayment(deviceId, paymentId) {
    const paymentResult = await db.query(
      `SELECT ep.id, ep.emi_schedule_id, ep.amount, ep.status
       FROM emi_payments ep
       JOIN emi_schedules es ON ep.emi_schedule_id = es.id
       WHERE ep.id = $1 AND es.device_id = $2 AND ep.status = 'completed'`,
      [paymentId, deviceId]
    );

    if (paymentResult.rows.length === 0) {
      return false;
    }

    const result = await db.query(
      `SELECT es.total_amount,
              COALESCE(SUM(ep.amount), 0) as total_paid
       FROM emi_schedules es
       LEFT JOIN emi_payments ep ON ep.emi_schedule_id = es.id AND ep.status = 'completed'
       WHERE es.device_id = $1 AND es.status = 'active'
       GROUP BY es.id, es.total_amount`,
      [deviceId]
    );

    if (result.rows.length === 0) return false;

    const { total_amount, total_paid } = result.rows[0];
    const totalAmountCents = Math.round(parseFloat(total_amount) * 100);
    const totalPaidCents = Math.round(parseFloat(total_paid) * 100);
    return totalPaidCents >= totalAmountCents;
  }

  async getDecouplingStats() {
    const result = await db.query(
      `SELECT state, COUNT(*) as count
       FROM decoupling
       GROUP BY state`
    );
    return result.rows;
  }
}

module.exports = new DecouplingModel();
module.exports.DECOUPLING_STATES = DECOUPLING_STATES;
module.exports.VALID_TRANSITIONS = VALID_TRANSITIONS;
module.exports.beginTransaction = beginTransaction;
module.exports.commitTransaction = commitTransaction;
module.exports.rollbackTransaction = rollbackTransaction;
