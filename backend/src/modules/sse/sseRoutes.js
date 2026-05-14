const express = require('express');

const router = express.Router();
const { authenticateToken } = require('../../middleware/auth');
const sseService = require('./sseService');
const db = require('../../config/database');
const logger = require('../../utils/logger');

const HEARTBEAT_INTERVAL_MS = 25000; // 25s — keeps connection alive through proxies

/**
 * GET /api/v1/events
 *
 * SSE stream. Authenticated users connect here and receive push
 * events in real time without polling.
 *
 * Browser (admin panel):
 *   const es = new EventSource('/api/v1/events', { withCredentials: true });
 *   es.addEventListener('device_locked', e => console.log(JSON.parse(e.data)));
 *
 * Flutter (dealer app):
 *   Use the `eventsource` pub.dev package or HTTP chunked streaming.
 */
router.get('/', authenticateToken, async (req, res) => {
  const userId = String(req.user.id);
  const { role } = req.user;

  // For dealers, look up their dealers.id so pushToDealer can find them
  let dealerId = null;
  if (role === 'dealer') {
    try {
      const r = await db.query('SELECT id FROM dealers WHERE user_id = $1 LIMIT 1', [userId]);
      if (r.rows.length) dealerId = String(r.rows[0].id);
    } catch (e) {
      logger.warn('SSE: failed to resolve dealer ID', { userId, error: e.message });
    }
  }

  // SSE required headers
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // disable Nginx buffering
  res.flushHeaders();

  // Send initial connected event so client knows stream is live
  res.write(
    `event: connected\ndata: ${JSON.stringify({
      userId,
      role,
      serverTime: new Date().toISOString(),
      message: 'Real-time stream connected'
    })}\n\n`
  );

  sseService.addClient(userId, role, res, dealerId);

  logger.info(
    `SSE client connected: userId=${userId} role=${role} total=${sseService.clientCount()}`
  );

  // Heartbeat — prevents idle timeout on proxies and mobile networks
  const heartbeat = setInterval(() => {
    try {
      res.write('event: heartbeat\ndata: {}\n\n');
    } catch (_) {
      clearInterval(heartbeat);
    }
  }, HEARTBEAT_INTERVAL_MS);

  // Clean up when client disconnects
  req.on('close', () => {
    clearInterval(heartbeat);
    sseService.removeClient(userId);
    logger.info(`SSE client disconnected: userId=${userId} total=${sseService.clientCount()}`);
  });
});

/**
 * GET /api/v1/events/status
 * Returns how many clients are currently connected.
 * Admin only — useful for monitoring.
 */
router.get('/status', authenticateToken, (req, res) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Admin only' });
  }
  res.json({ connected_clients: sseService.clientCount() });
});

module.exports = router;
