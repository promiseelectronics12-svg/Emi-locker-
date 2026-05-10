const { Router } = require('express');
const crypto = require('crypto');
const { body, validationResult } = require('express-validator');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole, ROLES } = require('../../middleware/rbac');
const db = require('../../config/database');
const {
  sendDealerMessage,
  getDeviceMessageStats,
  markNotificationDelivered,
} = require('./notification.service');

const router = Router();

const sendMessageValidation = [
  body('deviceId')
    .isString()
    .notEmpty()
    .withMessage('Device ID is required')
    .matches(/^[a-zA-Z0-9-_]{1,128}$/)
    .withMessage('Invalid device ID format'),
  body('message')
    .isString()
    .notEmpty()
    .withMessage('Message is required')
    .isLength({ max: 500 })
    .withMessage('Message must be 500 characters or less'),
];

router.post(
  '/message',
  authenticateToken,
  requireRole(ROLES.DEALER, ROLES.ADMIN),
  sendMessageValidation,
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        errors: errors.array(),
      });
    }

    const { deviceId, message } = req.body;
    const isAdmin = req.user.role === ROLES.ADMIN;
    const dealerName = req.user.name || 'Dealer';

    try {
      // Resolve actual dealers.id — JWT only has users.id
      const dealerRow = await db.query(
        `SELECT id FROM dealers WHERE user_id = $1 LIMIT 1`, [req.user.id]
      );
      const dealerId = dealerRow.rows[0]?.id || req.user.id;

      const result = await sendDealerMessage(deviceId, message, dealerId, dealerName, isAdmin, req.user.id);

      if (!result.success) {
        if (result.error && result.error.includes('Daily message limit')) {
          return res.status(429).json({
            success: false,
            error: result.error,
            rateLimit: {
              limit: result.rateLimit.limit,
              remaining: 0,
              resetAt: result.rateLimit.resetAt,
            },
          });
        }

        if (result.error === 'Device not found') {
          return res.status(404).json({
            success: false,
            error: 'Device not found',
          });
        }

        return res.status(500).json({
          success: false,
          error: result.error,
        });
      }

      return res.status(200).json({
        success: true,
        notificationId: result.notificationId,
        rateLimit: {
          limit: result.rateLimit.limit,
          remaining: result.rateLimit.limit - result.rateLimit.currentCount,
          resetAt: result.rateLimit.resetAt,
        },
      });
    } catch (error) {
      console.error('Send dealer message error:', error);
      return res.status(500).json({
        success: false,
        error: 'Internal server error',
      });
    }
  }
);

router.get(
  '/stats/:deviceId',
  authenticateToken,
  requireRole(ROLES.DEALER, ROLES.ADMIN),
  async (req, res) => {
    const { deviceId } = req.params;

    if (!deviceId || !/^[a-zA-Z0-9-_]{1,128}$/.test(deviceId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid device ID',
      });
    }

    try {
      const stats = await getDeviceMessageStats(deviceId);
      return res.status(200).json({
        success: true,
        stats,
      });
    } catch (error) {
      console.error('Get message stats error:', error);
      return res.status(500).json({
        success: false,
        error: 'Internal server error',
      });
    }
  }
);

router.post(
  '/delivery-receipt',
  async (req, res, next) => {
    const apiKey = req.headers['x-api-key'];
    const expectedKey = process.env.FCM_WEBHOOK_API_KEY;

    if (!expectedKey) {
      console.error('FCM_WEBHOOK_API_KEY not configured - rejecting delivery receipt');
      return res.status(503).json({
        success: false,
        error: 'Service not configured',
      });
    }

    if (!apiKey || !crypto.timingSafeEqual(Buffer.from(apiKey), Buffer.from(expectedKey))) {
      return res.status(401).json({
        success: false,
        error: 'Invalid API key',
      });
    }

    const { notificationId, fcmMessageId } = req.body;

    if (!notificationId || !fcmMessageId) {
      return res.status(400).json({
        success: false,
        error: 'notificationId and fcmMessageId are required',
      });
    }

    try {
      await markNotificationDelivered(notificationId, fcmMessageId);
      return res.status(200).json({ success: true });
    } catch (error) {
      console.error('Mark delivery error:', error);
      return res.status(500).json({
        success: false,
        error: 'Internal server error',
      });
    }
  }
);

module.exports = router;
