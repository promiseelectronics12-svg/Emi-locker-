const express = require('express');

const router = express.Router();
const fraudController = require('./fraudController');
const { authenticateToken } = require('../../middleware/auth');
const { requireRole } = require('../../middleware/rbac');
const { authenticateDevice } = require('../../middleware/deviceAuth');

router.post('/integrity-report', authenticateDevice, fraudController.handleIntegrityReport);
router.post(
  '/events',
  authenticateToken,
  requireRole('admin', 'dealer', 'reseller'),
  fraudController.createSecurityEvent
);
router.post(
  '/resolve/:eventId',
  authenticateToken,
  requireRole('admin'),
  fraudController.resolveSecurityEvent
);
router.get('/events', authenticateToken, requireRole('admin'), fraudController.getSecurityEvents);
router.get(
  '/events/:eventId',
  authenticateToken,
  requireRole('admin'),
  fraudController.getSecurityEvent
);
router.get('/neir-queue', authenticateToken, requireRole('admin'), fraudController.getNeirQueue);
router.get(
  '/neir-export',
  authenticateToken,
  requireRole('admin'),
  fraudController.exportNeirReport
);
router.get(
  '/anomalies/summary',
  authenticateToken,
  requireRole('admin'),
  fraudController.getAnomalySummary
);

module.exports = router;
