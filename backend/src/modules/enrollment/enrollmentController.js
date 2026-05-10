const { validationResult } = require('express-validator');
const logger = require('../../utils/logger');
const db = require('../../config/database');
const { startEnrollment } = require('./enrollmentService');

async function createEnrollment(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Validation failed', details: errors.array() });
  }

  try {
    // JWT payload has no dealer_id — look it up from dealers table
    const dealerRow = await db.query(
      `SELECT id FROM dealers WHERE user_id = $1 LIMIT 1`,
      [req.user.id]
    );
    const dealerId = dealerRow.rows[0]?.id || req.user.id;

    const result = await startEnrollment({
      dealerId,
      ...req.body,
    });
    // result = { enrollment_id, token }
    // token is plaintext — dealer app shows it on screen for dealer to type into user app
    return res.status(201).json(result);
  } catch (err) {
    const status = err.statusCode || 500;
    if (status >= 500) logger.error('createEnrollment failed', { error: err.message });
    return res.status(status).json({ error: err.message || 'Enrollment creation failed' });
  }
}

module.exports = { createEnrollment };
