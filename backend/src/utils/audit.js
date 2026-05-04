const db = require('../config/database');

async function createAuditLog(userId, action, metadata = {}) {
  try {
    await db.query(
      `INSERT INTO audit_logs (user_id, action, metadata, created_at)
       VALUES ($1, $2, $3, NOW())`,
      [userId, action, JSON.stringify(metadata)]
    );
  } catch (error) {
    console.error('Audit log error:', error);
  }
}

async function getAuditLogs(filters = {}) {
  const { userId, action, startDate, endDate, limit = 100 } = filters;

  let query = 'SELECT * FROM audit_logs WHERE 1=1';
  const params = [];
  let paramIndex = 1;

  if (userId) {
    query += ` AND user_id = $${paramIndex++}`;
    params.push(userId);
  }

  if (action) {
    query += ` AND action = $${paramIndex++}`;
    params.push(action);
  }

  if (startDate) {
    query += ` AND created_at >= $${paramIndex++}`;
    params.push(startDate);
  }

  if (endDate) {
    query += ` AND created_at <= $${paramIndex++}`;
    params.push(endDate);
  }

  query += ` ORDER BY created_at DESC LIMIT $${paramIndex}`;
  params.push(limit);

  const result = await db.query(query, params);
  return result.rows;
}

module.exports = {
  createAuditLog,
  getAuditLogs
};