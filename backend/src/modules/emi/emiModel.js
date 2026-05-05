const db = require('../../config/database');
const { v4: uuidv4 } = require('uuid');
const logger = require('../../utils/logger');

class EmiModel {
  async createSchedule({ deviceId, totalAmount, downPayment, emiAmount, duration, startDate, graceDays = 7, dealerId }) {
    const id = uuidv4();

    const result = await db.query(
      `INSERT INTO emi_schedules (
        id, device_id, total_amount, down_payment, emi_amount, duration,
        start_date, grace_days, status, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'active', NOW(), NOW())
      RETURNING *`,
      [id, deviceId, totalAmount, downPayment, emiAmount, duration, startDate, graceDays]
    );

    await this.logAuditEvent({
      actor: dealerId,
      actorType: 'dealer',
      action: 'EMI_SCHEDULE_CREATED',
      deviceId,
      metadata: { scheduleId: id, totalAmount, downPayment, emiAmount, duration, startDate, graceDays }
    });

    return result.rows[0];
  }

  async getScheduleByDeviceId(deviceId) {
    const result = await db.query(
      `SELECT es.*,
              d.device_name, d.imei, d.model, d.brand,
              dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM emi_schedules es
       JOIN devices d ON es.device_id = d.id
       JOIN dealers dl ON d.dealer_id = dl.id
       WHERE es.device_id = $1 AND es.status != 'cancelled'
       ORDER BY es.created_at DESC
       LIMIT 1`,
      [deviceId]
    );

    return result.rows[0] || null;
  }

  async getFullScheduleWithPayments(deviceId) {
    const scheduleResult = await db.query(
      `SELECT es.*,
              d.device_name, d.imei, d.model, d.brand, d.owner_id,
              dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM emi_schedules es
       JOIN devices d ON es.device_id = d.id
       JOIN dealers dl ON d.dealer_id = dl.id
       WHERE es.device_id = $1 AND es.status != 'cancelled'
       ORDER BY es.created_at DESC
       LIMIT 1`,
      [deviceId]
    );

    if (scheduleResult.rows.length === 0) {
      return null;
    }

    const schedule = scheduleResult.rows[0];

    const installmentsResult = await db.query(
      `SELECT ei.*,
              ep.id as payment_id, ep.amount as paid_amount, ep.payment_date,
              ep.payment_method, ep.transaction_ref, ep.payment_status,
              ep.recorded_at
       FROM generate_installments($1, $2, $3, $4) ei
       LEFT JOIN LATERAL (
         SELECT id, amount, payment_date, payment_method, transaction_ref, payment_status, recorded_at
         FROM emi_payments
         WHERE emi_schedule_id = es.id AND installment_number = ei.installment_number AND payment_status = 'completed'
         ORDER BY recorded_at DESC
         LIMIT 1
       ) ep ON true
       CROSS JOIN LATERAL (SELECT id FROM emi_schedules WHERE device_id = $1 ORDER BY created_at DESC LIMIT 1) es
       WHERE ei.schedule_id = es.id
       ORDER BY ei.installment_number`,
      [deviceId, schedule.total_amount, schedule.emi_amount, schedule.duration]
    );

    const paymentsResult = await db.query(
      `SELECT * FROM emi_payments
       WHERE device_id = $1
       ORDER BY payment_date DESC, recorded_at DESC`,
      [deviceId]
    );

    schedule.installments = installmentsResult.rows;
    schedule.payments = paymentsResult.rows;

    return schedule;
  }

  async recordPayment({ deviceId, scheduleId, amount, method, txId, installmentNumber = null, note = null, recordedBy }) {
    const id = uuidv4();

    const paymentResult = await db.query(
      `INSERT INTO emi_payments (
        id, emi_schedule_id, device_id, amount, payment_method, transaction_ref,
        installment_number, note, payment_status, recorded_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending', NOW())
      RETURNING *`,
      [id, scheduleId, deviceId, amount, method, txId, installmentNumber, note]
    );

    const verifyResult = await db.query(
      `SELECT ep.*, es.total_amount, es.emi_amount, es.duration
       FROM emi_payments ep
       JOIN emi_schedules es ON ep.emi_schedule_id = es.id
       WHERE ep.id = $1`,
      [id]
    );

    const payment = verifyResult.rows[0];

    const scheduleResult = await db.query(
      `SELECT * FROM emi_schedules WHERE id = $1`,
      [scheduleId]
    );
    const schedule = scheduleResult.rows[0];

    const totalPaidResult = await db.query(
      `SELECT COALESCE(SUM(amount), 0) as total_paid
       FROM emi_payments
       WHERE emi_schedule_id = $1 AND payment_status = 'completed'`,
      [scheduleId]
    );
    const totalPaid = parseFloat(totalPaidResult.rows[0].total_paid);

    const expectedTotal = parseFloat(schedule.total_amount);
    const remaining = expectedTotal - totalPaid;

    let newStatus = 'pending';
    if (remaining <= 0) {
      newStatus = 'completed';
    } else if (totalPaid >= parseFloat(schedule.down_payment)) {
      newStatus = 'active';
    }

    await db.query(
      `UPDATE emi_payments SET payment_status = $1, verified_at = NOW(), verified_by = $2 WHERE id = $3`,
      [newStatus, recordedBy, id]
    );

    await this.logAuditEvent({
      actor: recordedBy,
      actorType: 'system',
      action: 'EMI_PAYMENT_RECORDED',
      deviceId,
      metadata: {
        paymentId: id,
        amount,
        method,
        txId,
        installmentNumber,
        newStatus,
        totalPaid,
        remaining
      }
    });

    return { ...payment, status: newStatus, total_paid: totalPaid, remaining };
  }

  async getOverdueStatus(deviceId) {
    const schedule = await this.getScheduleByDeviceId(deviceId);

    if (!schedule || schedule.status !== 'active') {
      return { deviceId, isOverdue: false, daysOverdue: 0, currentInstallment: null };
    }

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const installmentsResult = await db.query(
      `SELECT * FROM calculate_due_dates($1, $2, $3, $4) AS due_date
       ORDER BY due_date`,
      [deviceId, schedule.start_date, schedule.emi_amount, schedule.duration]
    );

    let currentInstallment = null;
    let daysOverdue = 0;
    let isOverdue = false;

    const totalPaidResult = await db.query(
      `SELECT COALESCE(SUM(amount), 0) as total_paid
       FROM emi_payments
       WHERE device_id = $1 AND payment_status = 'completed'`,
      [deviceId]
    );
    const totalPaid = parseFloat(totalPaidResult.rows[0].total_paid);
    const expectedPaid = parseFloat(schedule.down_payment);

    for (let i = 0; i < installmentsResult.rows.length; i++) {
      const dueDateStr = installmentsResult.rows[i].due_date;
      const dueDate = new Date(dueDateStr);
      dueDate.setHours(0, 0, 0, 0);

      const installmentNumber = i + 1;
      const installmentExpected = parseFloat(schedule.down_payment) + (installmentNumber * parseFloat(schedule.emi_amount));

      if (totalPaid < installmentExpected) {
        currentInstallment = installmentNumber;

        const graceEndDate = new Date(dueDate);
        graceEndDate.setDate(graceEndDate.getDate() + schedule.grace_days);

        if (today > graceEndDate) {
          isOverdue = true;
          const diffTime = Math.abs(today - graceEndDate);
          daysOverdue = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        } else if (today > dueDate) {
          isOverdue = true;
          const diffTime = Math.abs(today - dueDate);
          daysOverdue = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        }
        break;
      }
    }

    return {
      deviceId,
      scheduleId: schedule.id,
      isOverdue,
      daysOverdue,
      currentInstallment,
      schedule
    };
  }

  async requestGracePeriod(deviceId, reason = null) {
    const schedule = await this.getScheduleByDeviceId(deviceId);

    if (!schedule) {
      throw new Error('No active EMI schedule found for this device');
    }

    if (schedule.status !== 'active') {
      throw new Error('EMI schedule is not active');
    }

    const gracePeriodCountResult = await db.query(
      `SELECT COUNT(*) as count
       FROM grace_period_requests
       WHERE device_id = $1
       AND created_at > NOW() - INTERVAL '1 month'
       AND status IN ('approved', 'pending')`,
      [deviceId]
    );

    const recentGracePeriods = parseInt(gracePeriodCountResult.rows[0].count);

    if (recentGracePeriods >= 2) {
      throw new Error('Maximum grace period requests (2 per month) exceeded');
    }

    const id = uuidv4();

    const result = await db.query(
      `INSERT INTO grace_period_requests (
        id, device_id, schedule_id, reason, status, created_at
      ) VALUES ($1, $2, $3, $4, 'approved', NOW())
      RETURNING *`,
      [id, deviceId, schedule.id, reason]
    );

    await this.logAuditEvent({
      actor: 'system',
      actorType: 'system',
      action: 'GRACE_PERIOD_APPROVED',
      deviceId,
      metadata: { gracePeriodId: id, reason, daysAdded: 14 }
    });

    return result.rows[0];
  }

  async getUpcomingDueDevices(days = 7) {
    const result = await db.query(
      `SELECT DISTINCT d.id as device_id, d.device_name, d.imei, d.model, d.brand,
              es.id as schedule_id, es.emi_amount, es.start_date, es.grace_days,
              dl.name as dealer_name, dl.phone as dealer_phone, dl.email as dealer_email
       FROM devices d
       JOIN emi_schedules es ON d.id = es.device_id
       JOIN dealers dl ON d.dealer_id = dl.id
       WHERE es.status = 'active'
       AND d.status = 'enrolled'
       AND d.id IN (
         SELECT device_id FROM get_upcoming_emi_installments($1, $2)
       )
       ORDER BY d.id, es.start_date`,
      [days, new Date().toISOString()]
    );

    return result.rows;
  }

  async getDecouplingState(deviceId) {
    const result = await db.query(
      `SELECT * FROM decoupling_state
       WHERE device_id = $1
       ORDER BY created_at DESC
       LIMIT 1`,
      [deviceId]
    );

    return result.rows[0] || null;
  }

  async createDecouplingState(deviceId, scheduleId) {
    const existing = await this.getDecouplingState(deviceId);
    if (existing) {
      return existing;
    }

    const id = uuidv4();

    const result = await db.query(
      `INSERT INTO decoupling_state (
        id, device_id, schedule_id, state, dealer_notified_at, created_at, updated_at
      ) VALUES ($1, $2, $3, 'EMI_ACTIVE', NOW(), NOW(), NOW())
      RETURNING *`,
      [id, deviceId, scheduleId]
    );

    return result.rows[0];
  }

  async updateDecouplingState(deviceId, newState, additionalData = {}) {
    const allowedColumns = ['fraud_flag', 'fraud_flagged_by', 'fraud_flagged_at', 'fraud_reason', 'dealer_notified_at'];
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
    const result = await db.query(
      `UPDATE decoupling_state
       SET ${setClauses.join(', ')}
       WHERE device_id = $${paramIndex}
       RETURNING *`,
      values
    );

    return result.rows[0];
  }

  async flagFraud(deviceId, flaggedBy, reason = null) {
    const result = await db.query(
      `UPDATE decoupling_state
       SET fraud_flag = true,
           fraud_flagged_by = $1,
           fraud_flagged_at = NOW(),
           fraud_reason = $2,
           updated_at = NOW()
       WHERE device_id = $3
       RETURNING *`,
      [flaggedBy, reason, deviceId]
    );

    await this.logAuditEvent({
      actor: flaggedBy,
      actorType: 'dealer',
      action: 'FRAUD_FLAG_RAISED',
      deviceId,
      metadata: { reason }
    });

    return result.rows[0];
  }

  async markDealerNotified(deviceId) {
    const result = await db.query(
      `UPDATE decoupling_state
       SET dealer_notified_at = NOW(), updated_at = NOW()
       WHERE device_id = $1 AND state = 'FINAL_PAYMENT_RECEIVED'
       RETURNING *`,
      [deviceId]
    );

    return result.rows[0];
  }

  async markPendingAdminDecouple(deviceId) {
    const result = await db.query(
      `UPDATE decoupling_state
       SET state = 'PENDING_ADMIN_DECOUPLE', updated_at = NOW()
       WHERE device_id = $1 AND state = 'DEALER_NOTIFIED'
       RETURNING *`,
      [deviceId]
    );

    return result.rows[0];
  }

  async getDeviceById(deviceId) {
    const result = await db.query(
      `SELECT d.*, es.id as schedule_id, es.total_amount, es.emi_amount, es.status as emi_status
       FROM devices d
       LEFT JOIN emi_schedules es ON d.id = es.device_id AND es.status = 'active'
       WHERE d.id = $1`,
      [deviceId]
    );

    return result.rows[0] || null;
  }

  async updateEmiScheduleStatus(scheduleId, status) {
    const result = await db.query(
      `UPDATE emi_schedules SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
      [status, scheduleId]
    );

    return result.rows[0];
  }

  async getInstallmentsForDevice(deviceId) {
    const schedule = await this.getScheduleByDeviceId(deviceId);

    if (!schedule) {
      return [];
    }

    const result = await db.query(
      `SELECT * FROM calculate_due_dates($1, $2, $3, $4) AS due_date
       ORDER BY due_date`,
      [deviceId, schedule.start_date, schedule.emi_amount, schedule.duration]
    );

    return result.rows;
  }

  async logAuditEvent({ actor, actorType, action, deviceId, metadata = {} }) {
    try {
      await db.query(
        `INSERT INTO audit_log (actor, action, device_id, metadata, created_at)
         VALUES ($1, $2, $3, $4, NOW())`,
        [actor, action, deviceId, JSON.stringify({ ...metadata, actorType })]
      );
    } catch (error) {
      logger.error('Failed to write audit log:', error);
    }
  }
}

module.exports = new EmiModel();
