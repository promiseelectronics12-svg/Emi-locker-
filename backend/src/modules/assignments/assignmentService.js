const db = require('../../config/database');
const logger = require('../../utils/logger');

// In-memory cache: deviceId → { assignmentId, expiresAt }
// Avoids N+1 lookups when history writers call getActiveAssignment
// per-event. TTL 60 seconds.
const _cache = new Map();
const CACHE_TTL_MS = 60 * 1000;

function _cacheGet(deviceId) {
  const entry = _cache.get(deviceId);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    _cache.delete(deviceId);
    return null;
  }
  return entry.assignmentId;
}

function _cacheSet(deviceId, assignmentId) {
  _cache.set(deviceId, {
    assignmentId,
    expiresAt: Date.now() + CACHE_TTL_MS
  });
}

function _cacheInvalidate(deviceId) {
  _cache.delete(deviceId);
}

/**
 * Returns the UUID of the active device_assignment for a device.
 * Returns null if none found (unassigned or decoupled).
 * Cached 60 seconds per device.
 */
async function getActiveAssignment(deviceId) {
  const cached = _cacheGet(deviceId);
  if (cached !== undefined) return cached;

  const result = await db.query(
    `SELECT id FROM device_assignments
     WHERE device_id = $1 AND status = 'active'
     LIMIT 1`,
    [deviceId]
  );

  const assignmentId = result.rows[0]?.id ?? null;
  _cacheSet(deviceId, assignmentId);
  return assignmentId;
}

/**
 * Creates a new active assignment. Closes any existing active
 * assignment first (safety — the unique partial index prevents two
 * concurrent actives, but this handles edge cases cleanly).
 */
async function createAssignment(deviceId, { customerId, dealerId, emiScheduleId }, client) {
  const q = client || db;

  // Close any lingering active (shouldn't exist but be safe)
  await q.query(
    `UPDATE device_assignments
     SET status = 'closed', closed_at = NOW(), close_reason = 'admin_override', updated_at = NOW()
     WHERE device_id = $1 AND status = 'active'`,
    [deviceId]
  );

  const result = await q.query(
    `INSERT INTO device_assignments
       (device_id, customer_id, dealer_id, emi_schedule_id, status, assigned_at)
     VALUES ($1, $2, $3, $4, 'active', NOW())
     RETURNING id`,
    [deviceId, customerId ?? null, dealerId ?? null, emiScheduleId ?? null]
  );

  const assignmentId = result.rows[0].id;
  _cacheInvalidate(deviceId);
  logger.info(`Assignment created for device ${deviceId}`, { assignmentId });
  return assignmentId;
}

/**
 * Closes the active assignment for a device.
 * closeReason: 'decoupled' | 'resold' | 'reconnected' | 'admin_override'
 */
async function closeAssignment(deviceId, closeReason, client) {
  const q = client || db;

  const result = await q.query(
    `UPDATE device_assignments
     SET status = $2,
         closed_at = NOW(),
         close_reason = $3,
         updated_at = NOW()
     WHERE device_id = $1 AND status = 'active'
     RETURNING id`,
    [deviceId, closeReason === 'resold' ? 'resold' : closeReason === 'reconnected' ? 'reconnected' : 'closed', closeReason]
  );

  _cacheInvalidate(deviceId);

  if (result.rows.length === 0) {
    logger.warn(`closeAssignment: no active assignment found for device ${deviceId}`);
    return null;
  }

  logger.info(`Assignment closed for device ${deviceId}`, {
    assignmentId: result.rows[0].id,
    closeReason
  });
  return result.rows[0].id;
}

/**
 * Returns full assignment record for a device (active or by id).
 */
async function getAssignmentById(assignmentId) {
  const result = await db.query(
    `SELECT * FROM device_assignments WHERE id = $1`,
    [assignmentId]
  );
  return result.rows[0] ?? null;
}

async function getAssignmentHistory(deviceId) {
  const result = await db.query(
    `SELECT id, status, customer_id, dealer_id, emi_schedule_id,
            assigned_at, closed_at, close_reason
     FROM device_assignments
     WHERE device_id = $1
     ORDER BY assigned_at DESC`,
    [deviceId]
  );
  return result.rows;
}

module.exports = {
  getActiveAssignment,
  createAssignment,
  closeAssignment,
  getAssignmentById,
  getAssignmentHistory,
  invalidateCache: _cacheInvalidate
};
