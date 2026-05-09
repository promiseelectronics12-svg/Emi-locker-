const { validationResult } = require('express-validator');
const logger = require('../../utils/logger');
const { startEnrollment } = require('./enrollmentService');

async function createEnrollment(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Validation failed', details: errors.array() });
  }

  try {
    const result = await startEnrollment({
      dealerId: req.user.dealer_id || req.user.id,
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
