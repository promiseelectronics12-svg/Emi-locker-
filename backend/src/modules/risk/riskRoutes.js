const express = require('express');
const { authenticateToken, requireRole } = require('../../middleware/auth');
const ctrl = require('./riskController');

const router = express.Router();

// GET  /risk/:deviceId/score      — current score + signal history + decision history
router.get('/:deviceId/score', authenticateToken, requireRole('admin', 'reseller', 'dealer'), ctrl.getScore);

// POST /risk/:deviceId/signal     — record a signal (admin/system use)
router.post('/:deviceId/signal', authenticateToken, requireRole('admin'), ctrl.recordSignal);

// DELETE /risk/:deviceId/signal/:signalType — clear a resolved signal
router.delete('/:deviceId/signal/:signalType', authenticateToken, requireRole('admin'), ctrl.clearSignal);

// POST /risk/:deviceId/evaluate   — trigger immediate lock evaluation (admin)
router.post('/:deviceId/evaluate', authenticateToken, requireRole('admin'), ctrl.evaluateLock);

module.exports = router;
