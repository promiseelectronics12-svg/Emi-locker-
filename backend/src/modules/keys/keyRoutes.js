const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const keyController = require('./keyController');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');

const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Too many requests, please try again later' }
});

const requestLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  message: { error: 'Too many key requests, please try again later' }
});

const consumeLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  message: { error: 'Too many consume requests, please try again later' }
});

router.use(authenticateToken);
router.use(generalLimiter);

router.post('/request', requestLimiter, requireRole('reseller'), keyController.requestKeys);
router.post('/approve/:requestId', requireRole('admin'), keyController.approveKeyRequest);
router.post('/reject/:requestId', requireRole('admin'), keyController.rejectKeyRequest);
router.post('/assign', requireRole('reseller'), keyController.assignKeys);
router.post('/consume', consumeLimiter, requireRole('dealer'), keyController.consumeKey);

module.exports = router;