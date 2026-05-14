const express = require('express');
const { body, param, query, validationResult } = require('express-validator');
const { v4: uuidv4 } = require('uuid');
const db = require('../config/database');
const logger = require('../config/logger');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

const generateEmiNumber = () => {
  const timestamp = Date.now().toString(36).toUpperCase();
  const random = Math.random().toString(36).substring(2, 6).toUpperCase();
  return `EMI-${timestamp}-${random}`;
};

router.post(
  '/',
  authenticateToken,
  [
    body('userId').isUUID(),
    body('deviceId').isUUID(),
    body('totalAmount').isFloat({ min: 0 }),
    body('downPayment').isFloat({ min: 0 }),
    body('tenureMonths').isInt({ min: 1, max: 60 }),
    body('interestRate').optional().isFloat({ min: 0, max: 100 }),
    body('startDate').isISO8601(),
    body('paymentDueDay').optional().isInt({ min: 1, max: 28 }),
    body('notes').optional().trim()
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const {
        userId,
        deviceId,
        totalAmount,
        downPayment,
        tenureMonths,
        interestRate = 0,
        startDate,
        paymentDueDay = 5,
        notes
      } = req.body;

      const user = await db.query('SELECT id FROM users WHERE id = $1', [userId]);
      if (user.rows.length === 0) {
        return res.status(404).json({ error: 'User not found' });
      }

      const device = await db.query('SELECT id FROM devices WHERE id = $1', [deviceId]);
      if (device.rows.length === 0) {
        return res.status(404).json({ error: 'Device not found' });
      }

      const emiNumber = generateEmiNumber();
      const monthlyPayment = (totalAmount - downPayment) / tenureMonths;
      const endDate = new Date(startDate);
      endDate.setMonth(endDate.getMonth() + tenureMonths);

      const result = await db.query(
        `INSERT INTO emi_agreements 
         (emi_number, user_id, device_id, dealer_id, total_amount, monthly_payment, down_payment,
          tenure_months, interest_rate, start_date, end_date, payment_due_day, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
         RETURNING *`,
        [
          emiNumber,
          userId,
          deviceId,
          req.user.userId,
          totalAmount,
          monthlyPayment,
          downPayment,
          tenureMonths,
          interestRate,
          startDate,
          endDate,
          paymentDueDay,
          notes
        ]
      );

      await db.query('UPDATE devices SET status = $1 WHERE id = $2', ['locked', deviceId]);

      logger.info(`EMI agreement ${emiNumber} created`);

      res.status(201).json({
        message: 'EMI agreement created successfully',
        agreement: result.rows[0]
      });
    } catch (error) {
      logger.error('Create agreement error', error);
      res.status(500).json({ error: 'Failed to create agreement' });
    }
  }
);

router.get(
  '/',
  authenticateToken,
  [
    query('status').optional().isIn(['active', 'completed', 'defaulted', 'cancelled', 'disputed']),
    query('page').optional().isInt({ min: 1 }),
    query('limit').optional().isInt({ min: 1, max: 100 })
  ],
  async (req, res) => {
    try {
      const { status, page = 1, limit = 20 } = req.query;
      const offset = (page - 1) * limit;

      let query = `SELECT ea.*, u.name as user_name, u.phone as user_phone, d.imei
                   FROM emi_agreements ea
                   LEFT JOIN users u ON ea.user_id = u.id
                   LEFT JOIN devices d ON ea.device_id = d.id`;
      let countQuery = 'SELECT COUNT(*) FROM emi_agreements';
      const params = [];
      const countParams = [];

      if (status) {
        query += ' WHERE ea.status = $1';
        countQuery += ' WHERE status = $1';
        params.push(status);
        countParams.push(status);
      }

      query += ` ORDER BY ea.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(limit, offset);

      const [agreementsResult, countResult] = await Promise.all([
        db.query(query, params),
        db.query(countQuery, countParams)
      ]);

      res.json({
        agreements: agreementsResult.rows,
        pagination: {
          page: parseInt(page, 10),
          limit: parseInt(limit, 10),
          total: parseInt(countResult.rows[0].count, 10),
          pages: Math.ceil(countResult.rows[0].count / limit)
        }
      });
    } catch (error) {
      logger.error('Get agreements error', error);
      res.status(500).json({ error: 'Failed to fetch agreements' });
    }
  }
);

router.get(
  '/:agreementId',
  authenticateToken,
  [param('agreementId').isUUID()],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const result = await db.query(
        `SELECT ea.*, u.name as user_name, u.phone as user_phone, u.nid as user_nid,
                d.imei, d.model, d.manufacturer
         FROM emi_agreements ea
         LEFT JOIN users u ON ea.user_id = u.id
         LEFT JOIN devices d ON ea.device_id = d.id
         WHERE ea.id = $1`,
        [req.params.agreementId]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Agreement not found' });
      }

      const payments = await db.query(
        'SELECT * FROM payments WHERE agreement_id = $1 ORDER BY payment_date DESC',
        [req.params.agreementId]
      );

      res.json({
        agreement: result.rows[0],
        payments: payments.rows
      });
    } catch (error) {
      logger.error('Get agreement error', error);
      res.status(500).json({ error: 'Failed to fetch agreement' });
    }
  }
);

router.put(
  '/:agreementId/status',
  authenticateToken,
  [
    param('agreementId').isUUID(),
    body('status').isIn(['active', 'completed', 'defaulted', 'cancelled', 'disputed']),
    body('reason').optional().trim()
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const { status, reason } = req.body;
      const { agreementId } = req.params;

      const oldAgreement = await db.query('SELECT * FROM emi_agreements WHERE id = $1', [
        agreementId
      ]);
      if (oldAgreement.rows.length === 0) {
        return res.status(404).json({ error: 'Agreement not found' });
      }

      const result = await db.query(
        `UPDATE emi_agreements SET status = $1, updated_at = NOW()
         WHERE id = $2 RETURNING *`,
        [status, agreementId]
      );

      if (status === 'completed') {
        await db.query('UPDATE devices SET status = $1 WHERE id = $2', [
          'unlocked',
          oldAgreement.rows[0].device_id
        ]);
      }

      await db.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, old_value, new_value, ip_address)
         VALUES ($1, 'agreement_status_changed', 'agreement', $2, $3, $4, $5)`,
        [
          req.user.userId,
          agreementId,
          JSON.stringify(oldAgreement.rows[0]),
          JSON.stringify(result.rows[0]),
          req.ip
        ]
      );

      logger.info(`Agreement ${agreementId} status changed to ${status}`);

      res.json({
        message: 'Agreement status updated',
        agreement: result.rows[0]
      });
    } catch (error) {
      logger.error('Update agreement status error', error);
      res.status(500).json({ error: 'Failed to update agreement status' });
    }
  }
);

router.post(
  '/:agreementId/payments',
  authenticateToken,
  [
    param('agreementId').isUUID(),
    body('amount').isFloat({ min: 0 }),
    body('paymentDate').isISO8601(),
    body('paymentMethod').isIn(['cash', 'bank_transfer', 'mobile_banking', 'card']),
    body('transactionRef').optional().trim().isLength({ max: 100 })
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const { amount, paymentDate, paymentMethod, transactionRef } = req.body;
      const { agreementId } = req.params;

      const agreement = await db.query('SELECT * FROM emi_agreements WHERE id = $1', [agreementId]);
      if (agreement.rows.length === 0) {
        return res.status(404).json({ error: 'Agreement not found' });
      }

      const result = await db.query(
        `INSERT INTO payments (agreement_id, amount, payment_date, payment_method, transaction_ref, collected_by, status)
         VALUES ($1, $2, $3, $4, $5, $6, 'completed') RETURNING *`,
        [agreementId, amount, paymentDate, paymentMethod, transactionRef, req.user.userId]
      );

      logger.info(`Payment of ${amount} recorded for agreement ${agreementId}`);

      res.status(201).json({
        message: 'Payment recorded successfully',
        payment: result.rows[0]
      });
    } catch (error) {
      logger.error('Record payment error', error);
      res.status(500).json({ error: 'Failed to record payment' });
    }
  }
);

module.exports = router;
