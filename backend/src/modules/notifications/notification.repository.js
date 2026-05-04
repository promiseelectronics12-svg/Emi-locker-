const { pool } = require('../../config/database');

async function createNotificationRecord(record) {
  const query = `
    INSERT INTO notifications (
      device_id, type, title, body, payload, status,
      fcm_message_id, provider, delivered_at, failed_at, failure_reason
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    RETURNING id
  `;

  const values = [
    record.device_id,
    record.type,
    record.title || null,
    record.body || null,
    JSON.stringify(record.payload),
    record.status,
    record.fcm_message_id || null,
    record.provider,
    record.delivered_at || null,
    record.failed_at || null,
    record.failure_reason || null,
  ];

  const result = await pool.query(query, values);
  return result.rows[0].id;
}

async function updateNotificationStatus(
  id,
  status,
  options
) {
  const query = `
    UPDATE notifications
    SET status = $2,
        fcm_message_id = COALESCE($3, fcm_message_id),
        delivered_at = COALESCE($4, delivered_at),
        failed_at = COALESCE($5, failed_at),
        failure_reason = COALESCE($6, failure_reason),
        updated_at = NOW()
    WHERE id = $1
  `;

  const values = [
    id,
    status,
    options?.fcm_message_id ?? null,
    options?.delivered_at ?? null,
    options?.failed_at ?? null,
    options?.failure_reason ?? null,
  ];

  await pool.query(query, values);
}

async function findNotificationsByDevice(deviceId, limit = 50) {
  const query = `
    SELECT * FROM notifications
    WHERE device_id = $1
    ORDER BY created_at DESC
    LIMIT $2
  `;

  const result = await pool.query(query, [deviceId, limit]);
  return result.rows.map(row => ({
    ...row,
    payload: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
  }));
}

async function findPendingNotifications(deviceId, type) {
  let query = `
    SELECT * FROM notifications
    WHERE device_id = $1 AND status = 'PENDING'
  `;
  const values = [deviceId];

  if (type) {
    query += ` AND type = $2`;
    values.push(type);
  }

  const result = await pool.query(query, values);
  return result.rows.map(row => ({
    ...row,
    payload: typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload,
  }));
}

async function getNotificationStatsByDevice(deviceId, days = 30) {
  const query = `
    SELECT
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE status = 'DELIVERED') as delivered,
      COUNT(*) FILTER (WHERE status = 'FAILED') as failed,
      type,
      COUNT(*) as type_count
    FROM notifications
    WHERE device_id = $1 AND created_at > NOW() - make_interval(days => $2)
    GROUP BY type
  `;

  const result = await pool.query(query, [deviceId, days]);

  const stats = {
    total: 0,
    delivered: 0,
    failed: 0,
    byType: {},
  };

  for (const row of result.rows) {
    stats.total += parseInt(row.total, 10);
    stats.delivered += parseInt(row.delivered, 10);
    stats.failed += parseInt(row.failed, 10);
    stats.byType[row.type] = parseInt(row.type_count, 10);
  }

  return stats;
}

module.exports = {
  createNotificationRecord,
  updateNotificationStatus,
  findNotificationsByDevice,
  findPendingNotifications,
  getNotificationStatsByDevice,
};