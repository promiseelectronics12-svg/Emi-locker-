const { validationResult } = require('express-validator');
const { buildErrorResponse } = require('./errorHandler');

const validateRequest = (req, res, next) => {
  const errors = validationResult(req);

  if (!errors.isEmpty()) {
    return res.status(400).json({
      ...buildErrorResponse(400, 'VALIDATION_ERROR', 'Validation failed'),
      details: errors.array().map((err) => ({
        field: err.path,
        message: err.msg
      }))
    });
  }

  next();
};

module.exports = { validateRequest };
