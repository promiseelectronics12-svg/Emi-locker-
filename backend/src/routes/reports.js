const express = require('express');
const { body, validationResult } = require('express-validator');
const db = require('../config/database');
const logger = require('../config/logger');
const { authenticate, authorize } = require('../middleware/auth');

const router = express.Router();

router.post('/emi',
  authenticate,
  authorize(['admin', 'dealer']),
  [
    body('startDate').optional().isISO8601(),
    body('endDate').optional().isISO8601(),
    body('status').optional().isIn(['active', 'completed', 'defaulted', 'cancelled', 'disputed'])
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const { startDate, endDate, status } = req.query;

      let query = `
        SELECT 
          ea.id,
          ea.emi_number,
          u.name as user_name,
          u.phone as user_phone,
          u.nid as user_nid,
          d.imei,
          d.model,
          ea.total_amount,
          ea.down_payment,
          ea.monthly_payment,
          ea.tenure_months,
          ea.start_date,
          ea.end_date,
          ea.status as agreement_status,
          ea.risk_level,
          COALESCE(SUM(p.amount), 0) as total_paid,
          COUNT(p.id) as payment_count
        FROM emi_agreements ea
        LEFT JOIN users u ON ea.user_id = u.id
        LEFT JOIN devices d ON ea.device_id = d.id
        LEFT JOIN payments p ON ea.id = p.agreement_id AND p.status = 'completed'
        WHERE 1=1
      `;
      const params = [];
      let paramCount = 1;

      if (startDate) {
        query += ` AND ea.start_date >= $${paramCount++}`;
        params.push(startDate);
      }
      if (endDate) {
        query += ` AND ea.end_date <= $${paramCount++}`;
        params.push(endDate);
      }
      if (status) {
        query += ` AND ea.status = $${paramCount++}`;
        params.push(status);
      }

      query += ' GROUP BY ea.id, u.name, u.phone, u.nid, d.imei, d.model ORDER BY ea.created_at DESC';

      const result = await db.query(query, params);

      const summary = await db.query(`
        SELECT 
          COUNT(*) as total_agreements,
          SUM(total_amount) as total_value,
          SUM(down_payment) as total_down_payment,
          COUNT(CASE WHEN status = 'active' THEN 1 END) as active_count,
          COUNT(CASE WHEN status = 'defaulted' THEN 1 END) as defaulted_count,
          COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_count
        FROM emi_agreements
        ${status ? 'WHERE status = $1' : ''}
      `, status ? [status] : []);

      res.json({
        report: result.rows,
        summary: summary.rows[0]
      });
    } catch (error) {
      logger.error('EMI report error', error);
      res.status(500).json({ error: 'Failed to generate EMI report' });
    }
  }
);

router.post('/device',
  authenticate,
  authorize(['admin', 'dealer']),
  [
    body('startDate').optional().isISO8601(),
    body('endDate').optional().isISO8601(),
    body('status').optional().isIn(['pending', 'enrolled', 'locked', 'unlocked', 'lost', 'stolen'])
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const { startDate, endDate, status } = req.query;

      let query = `
        SELECT 
          d.id,
          d.imei,
          d.model,
          d.manufacturer,
          d.android_version,
          d.status as device_status,
          d.enrollment_date,
          d.last_seen,
          u.name as user_name,
          u.phone as user_phone,
          dl.name as dealer_name,
          COALESCE(ea.emi_number, 'N/A') as emi_number,
          COALESCE(ea.status, 'N/A') as agreement_status
        FROM devices d
        LEFT JOIN users u ON d.user_id = u.id
        LEFT JOIN dealers dl ON d.dealer_id = dl.id
        LEFT JOIN emi_agreements ea ON d.id = ea.device_id
        WHERE d.is_active = true
      `;
      const params = [];
      let paramCount = 1;

      if (startDate) {
        query += ` AND d.enrollment_date >= $${paramCount++}`;
        params.push(startDate);
      }
      if (endDate) {
        query += ` AND d.enrollment_date <= $${paramCount++}`;
        params.push(endDate);
      }
      if (status) {
        query += ` AND d.status = $${paramCount++}`;
        params.push(status);
      }

      query += ' ORDER BY d.enrollment_date DESC';

      const result = await db.query(query, params);

      const summary = await db.query(`
        SELECT 
          COUNT(*) as total_devices,
          COUNT(CASE WHEN status = 'enrolled' THEN 1 END) as enrolled_count,
          COUNT(CASE WHEN status = 'locked' THEN 1 END) as locked_count,
          COUNT(CASE WHEN status = 'unlocked' THEN 1 END) as unlocked_count,
          COUNT(CASE WHEN status IN ('lost', 'stolen') THEN 1 END) as flagged_count
        FROM devices
        WHERE is_active = true
      `);

      res.json({
        report: result.rows,
        summary: summary.rows[0]
      });
    } catch (error) {
      logger.error('Device report error', error);
      res.status(500).json({ error: 'Failed to generate device report' });
    }
  }
);

router.post('/collection',
  authenticate,
  authorize(['admin', 'dealer']),
  [
    body('startDate').optional().isISO8601(),
    body('endDate').optional().isISO8601()
  ],
  async (req, res) => {
    try {
      const { startDate, endDate } = req.query;

      let query = `
        SELECT 
          p.id,
          p.amount,
          p.payment_date,
          p.payment_method,
          p.transaction_ref,
          p.status,
          ea.emi_number,
          ea.id as agreement_id,
          u.name as user_name,
          u.phone as user_phone,
          dl.name as collected_by_name
        FROM payments p
        LEFT JOIN emi_agreements ea ON p.agreement_id = ea.id
        LEFT JOIN users u ON ea.user_id = u.id
        LEFT JOIN dealers dl ON p.collected_by = dl.id
        WHERE p.status = 'completed'
      `;
      const params = [];
      let paramCount = 1;

      if (startDate) {
        query += ` AND p.payment_date >= $${paramCount++}`;
        params.push(startDate);
      }
      if (endDate) {
        query += ` AND p.payment_date <= $${paramCount++}`;
        params.push(endDate);
      }

      query += ' ORDER BY p.payment_date DESC';

      const result = await db.query(query, params);

      const summary = await db.query(`
        SELECT 
          COUNT(*) as total_transactions,
          SUM(amount) as total_collection
        FROM payments
        WHERE status = 'completed'
        ${startDate ? 'AND payment_date >= $1' : ''}
        ${endDate ? 'AND payment_date <= $2' : ''}
      `, startDate && endDate ? [startDate, endDate] : startDate ? [startDate] : endDate ? [endDate] : []);

      res.json({
        report: result.rows,
        summary: summary.rows[0]
      });
    } catch (error) {
      logger.error('Collection report error', error);
      res.status(500).json({ error: 'Failed to generate collection report' });
    }
  }
);

module.exports = router;