const { body, param, query, validationResult } = require('express-validator');

const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

const scheduleValidation = [
  body('deviceId')
    .isUUID()
    .withMessage('Valid device ID is required'),
  body('totalAmount')
    .isFloat({ min: 0.01 })
    .withMessage('Total amount must be a positive number'),
  body('downPayment')
    .isFloat({ min: 0 })
    .withMessage('Down payment must be a non-negative number'),
  body('emiAmount')
    .isFloat({ min: 0.01 })
    .withMessage('EMI amount must be a positive number'),
  body('duration')
    .isInt({ min: 1, max: 60 })
    .withMessage('Duration must be between 1 and 60 months'),
  body('startDate')
    .isISO8601()
    .withMessage('Valid start date is required'),
  body('graceDays')
    .optional()
    .isInt({ min: 0, max: 30 })
    .withMessage('Grace days must be between 0 and 30'),
  body('dealerId')
    .isUUID()
    .withMessage('Valid dealer ID is required')
];

const deviceIdParam = param('deviceId')
  .isUUID()
  .withMessage('Valid device ID is required');

const paymentValidation = [
  body('amount')
    .isFloat({ min: 0.01 })
    .withMessage('Payment amount must be a positive number'),
  body('method')
    .isIn(['cash', 'bank_transfer', 'bKash', 'nagad', 'rocket', 'card', 'other'])
    .withMessage('Valid payment method is required'),
  body('txId')
    .optional()
    .isString()
    .isLength({ max: 255 })
    .withMessage('Transaction ID must be a string with max 255 characters'),
  body('installmentNumber')
    .optional()
    .isInt({ min: 1 })
    .withMessage('Installment number must be a positive integer'),
  body('note')
    .optional()
    .isString()
    .isLength({ max: 500 })
    .withMessage('Note must be a string with max 500 characters')
];

const gracePeriodValidation = [
  body('reason')
    .optional()
    .isString()
    .isLength({ max: 500 })
    .withMessage('Reason must be a string with max 500 characters')
];

const upcomingQueryValidation = [
  query('days')
    .optional()
    .isInt({ min: 1, max: 30 })
    .withMessage('Days must be between 1 and 30')
];

const deviceIdParamValidation = param('deviceId')
  .isUUID()
  .withMessage('Valid device ID is required');

module.exports = {
  validateRequest,
  scheduleValidation,
  deviceIdParam,
  paymentValidation,
  gracePeriodValidation,
  upcomingQueryValidation,
  deviceIdParamValidation
};