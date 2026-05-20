const express = require('express');
const { authenticateToken, requireRole } = require('../../middleware/auth');
const { googleAuth, registerFcmToken, getDevice, getSchedule } = require('./customerController');

const router = express.Router();

// Public — exchange Google ID token for app JWT
router.post('/auth/google', googleAuth);

// Authenticated customer routes
router.post('/fcm-token', authenticateToken, requireRole('customer'), registerFcmToken);
router.get('/devices/:imei', authenticateToken, requireRole('customer'), getDevice);
router.get('/schedule', authenticateToken, requireRole('customer'), getSchedule);

module.exports = router;
