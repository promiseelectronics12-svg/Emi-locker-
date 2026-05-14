const express = require('express');

const router = express.Router();
const asyncHandler = require('express-async-handler');
const { body, query, param, validationResult } = require('express-validator');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');
const adminMiddleware = require('./adminMiddleware');
const adminController = require('./adminController');
const errorStore = require('../../utils/errorStore');

const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

router.use(authenticateToken);
router.use(requireRole('admin'));
router.use(adminMiddleware.requireVerified2FA);
router.use(adminMiddleware.logAdminAction);

router.get('/dashboard', asyncHandler(adminController.getDashboardStats));

// ── Districts & Reseller Distribution ─────────────────────────────────────────
router.get('/districts/summary', asyncHandler(adminController.getDistrictSummary));

router.get(
  '/districts/:district/resellers',
  [param('district').isString().trim().isLength({ min: 2, max: 64 })],
  validateRequest,
  asyncHandler(adminController.getResellersByDistrict)
);

router.get(
  '/resellers/:id/stats',
  [param('id').isUUID()],
  validateRequest,
  asyncHandler(adminController.getResellerStats)
);

// ── Resellers ─────────────────────────────────────────────────────────────────
router.get(
  '/resellers',
  [
    query('status').optional().isIn(['pending', 'active', 'suspended']),
    query('search').optional().isString().trim(),
    query('limit').optional().isInt({ min: 1, max: 100 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getResellers)
);

// Invite routes must come before /:id routes to avoid "invite" matching as :id
router.post(
  '/resellers/invite',
  [
    body('email').isEmail().normalizeEmail(),
    body('name').isString().trim().isLength({ min: 2, max: 100 })
  ],
  validateRequest,
  asyncHandler(adminController.inviteReseller)
);

router.get(
  '/resellers/invite/verify',
  [query('token').isString().isLength({ min: 32 })],
  validateRequest,
  asyncHandler(adminController.verifyResellerInvite)
);

router.post(
  '/resellers/invite/complete',
  [
    body('token').isString().isLength({ min: 32 }),
    body('password').isString().isLength({ min: 8 }),
    body('photoUrl').optional().isURL()
  ],
  validateRequest,
  asyncHandler(adminController.completeResellerInvite)
);

router.post(
  '/resellers/:id/approve',
  [param('id').isUUID(), body('confirmationCode').optional().isString()],
  validateRequest,
  asyncHandler(adminController.approveReseller)
);

router.post(
  '/resellers/:id/suspend',
  [param('id').isUUID(), body('reason').isString().trim().isLength({ min: 10, max: 500 })],
  validateRequest,
  asyncHandler(adminController.suspendReseller)
);

router.post(
  '/resellers/:id/quota',
  [param('id').isUUID(), body('monthlyQuota').isInt({ min: 1, max: 10000 })],
  validateRequest,
  asyncHandler(adminController.setResellerQuota)
);

router.get(
  '/devices',
  [
    query('status')
      .optional()
      .isIn(['active', 'locked', 'unlocked', 'disabled', 'enrolled', 'pending_decouple']),
    query('dealerId').optional().isUUID(),
    query('resellerId').optional().isUUID(),
    query('imei').optional().isString().trim(),
    query('search').optional().isString().trim(),
    query('emiStatus').optional().isIn(['active', 'overdue', 'paid_off', 'cancelled']),
    query('limit').optional().isInt({ min: 1, max: 500 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getDevices)
);

router.get(
  '/devices/:id',
  [param('id').isUUID()],
  validateRequest,
  asyncHandler(adminController.getDeviceById)
);

router.post(
  '/devices/:id/action',
  [
    param('id').isUUID(),
    body('type').isIn(['LOCK', 'UNLOCK']),
    body('reason').optional().isString().trim().isLength({ min: 5, max: 500 }),
    body('twoFactorCode').optional().isString()
  ],
  validateRequest,
  asyncHandler(adminController.executeDeviceAction)
);

router.post(
  '/devices/:id/lock',
  [
    param('id').isUUID(),
    body('reason').isString().trim().isLength({ min: 5, max: 500 }),
    body('lockLevel').optional().isIn(['soft', 'hard', 'wipe'])
  ],
  validateRequest,
  asyncHandler(adminController.lockDevice)
);

router.post(
  '/devices/:id/unlock',
  [param('id').isUUID(), body('reason').isString().trim().isLength({ min: 5, max: 500 })],
  validateRequest,
  asyncHandler(adminController.unlockDevice)
);

router.get(
  '/audit-log',
  [
    query('actor').optional().isString(),
    query('action').optional().isString().trim(),
    query('targetType').optional().isIn(['device', 'user', 'reseller', 'dealer', 'key', 'payment']),
    query('targetId').optional().isString(),
    query('ipAddress').optional().isString(),
    query('startDate').optional().isISO8601(),
    query('endDate').optional().isISO8601(),
    query('limit').optional().isInt({ min: 1, max: 500 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getAuditLog)
);

router.get(
  '/security-events',
  [
    query('severity').optional().isIn(['low', 'medium', 'high', 'critical']),
    query('eventType').optional().isString().trim(),
    query('startDate').optional().isISO8601(),
    query('endDate').optional().isISO8601(),
    query('limit').optional().isInt({ min: 1, max: 500 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getSecurityEvents)
);

router.patch(
  '/security-events/:id',
  [
    param('id').isUUID(),
    body('status').optional().isIn(['RESOLVED']),
    body('resolution').optional().isString().trim()
  ],
  validateRequest,
  asyncHandler(adminController.resolveSecurityEvent)
);

router.get('/neir-queue', asyncHandler(adminController.getNeirQueue));

router.post(
  '/neir-queue/report',
  [body('imei').isString().trim().isLength({ min: 8, max: 50 })],
  validateRequest,
  asyncHandler(adminController.reportNeirQueueItem)
);

router.post(
  '/neir-queue',
  [body('deviceId').isUUID(), body('reason').isString().trim().isLength({ min: 10, max: 1000 })],
  validateRequest,
  asyncHandler(adminController.addToNeirQueue)
);

router.get('/decoupling/pending', asyncHandler(adminController.getPendingDecoupling));

router.get(
  '/key-requests',
  [
    query('status').optional().isIn(['pending', 'approved', 'rejected']),
    query('resellerId').optional().isUUID(),
    query('limit').optional().isInt({ min: 1, max: 500 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getKeyRequests)
);

router.post(
  '/key-requests/:id/approve',
  [param('id').isUUID(), body('quantity').isInt({ min: 1, max: 1000 })],
  validateRequest,
  asyncHandler(adminController.approveKeyRequest)
);

router.post(
  '/key-requests/:id/reject',
  [param('id').isUUID(), body('rejectionReason').isString().trim().isLength({ min: 5, max: 500 })],
  validateRequest,
  asyncHandler(adminController.rejectKeyRequest)
);

// ── Dealers ───────────────────────────────────────────────────────────────────
router.get(
  '/dealers',
  [
    query('status').optional().isIn(['active', 'suspended', 'pending']),
    query('resellerId').optional().isUUID(),
    query('search').optional().isString().trim(),
    query('limit').optional().isInt({ min: 1, max: 200 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validateRequest,
  asyncHandler(adminController.getDealers)
);

router.post(
  '/dealers/:id/suspend',
  [param('id').isUUID(), body('reason').isString().trim().isLength({ min: 5, max: 500 })],
  validateRequest,
  asyncHandler(adminController.suspendDealer)
);

router.post(
  '/dealers/:id/activate',
  [param('id').isUUID()],
  validateRequest,
  asyncHandler(adminController.activateDealer)
);

// ── Universal search ──────────────────────────────────────────────────────────
router.get(
  '/search',
  [query('q').isString().trim().isLength({ min: 2, max: 100 })],
  validateRequest,
  asyncHandler(adminController.universalSearch)
);

// ── Key inventory ─────────────────────────────────────────────────────────────
router.get(
  '/keys/inventory',
  [
    query('tier').optional().isIn(['standard', 'premium', 'vip']),
    query('resellerId').optional().isUUID()
  ],
  validateRequest,
  asyncHandler(adminController.getKeyInventory)
);

// ── Error monitor ─────────────────────────────────────────────────────────────
// Returns recent server errors with file:line origin for developer visibility.
router.get(
  '/errors',
  [query('limit').optional().isInt({ min: 1, max: 100 })],
  validateRequest,
  (req, res) => {
    const limit = parseInt(req.query.limit, 10) || 50;
    const errors = errorStore.recent(limit);
    res.json({ count: errors.length, errors });
  }
);

module.exports = router;
