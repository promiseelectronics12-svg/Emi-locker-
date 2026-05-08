const { validationResult } = require('express-validator');
const logger = require('../../utils/logger');
const { verifyStagingActivation } = require('./deviceActivationService');

async function verifyActivation(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ error: 'Invalid activation request', details: errors.array() });
  }

  try {
    const result = await verifyStagingActivation(req.body);
    return res.status(200).json(result);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    if (statusCode >= 500) {
      logger.error('Device activation verification failed:', error);
    }

    return res.status(statusCode).json({
      success: false,
      error: statusCode >= 500 ? 'Activation verification failed' : error.message
    });
  }
}

module.exports = {
  verifyActivation
};
