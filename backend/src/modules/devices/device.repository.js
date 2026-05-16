const db = require('../../config/database');

async function getDeviceById(deviceId) {
  const query = `
    SELECT d.*,
           u.phone as customer_phone,
           dl.phone as dealer_phone
    FROM devices d
    LEFT JOIN users u ON d.owner_id = u.id
    LEFT JOIN dealers dl ON d.dealer_id = dl.id
    WHERE d.id = $1
  `;

  const result = await db.query(query, [deviceId]);

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0];
  return {
    id: row.id,
    imei: row.imei,
    serial: row.serial,
    soc_model: row.soc_model,
    owner_id: row.owner_id,
    dealer_id: row.dealer_id,
    status: row.status,
    lock_level: row.lock_level,
    state: row.state,
    amapi_device_id: row.amapi_device_id,
    fcm_token: row.fcm_token,
    phone: row.customer_phone,
    dealer_phone: row.dealer_phone,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function updateDeviceFCMToken(deviceId, fcmToken) {
  const query = `
    UPDATE devices
    SET fcm_token = $2, updated_at = NOW()
    WHERE id = $1
  `;
  await db.query(query, [deviceId, fcmToken]);
}

async function getDeviceByIMEI(imei) {
  const query = `SELECT * FROM devices WHERE imei = $1`;
  const result = await db.query(query, [imei]);

  if (result.rows.length === 0) {
    return null;
  }

  return result.rows[0];
}

async function getDevicesByDealer(dealerId) {
  const query = `SELECT * FROM devices WHERE dealer_id = $1 ORDER BY created_at DESC`;
  const result = await db.query(query, [dealerId]);
  return result.rows;
}

async function getDevicesByCustomer(customerId) {
  const query = `SELECT * FROM devices WHERE owner_id = $1 ORDER BY created_at DESC`;
  const result = await db.query(query, [customerId]);
  return result.rows;
}

async function updateDeviceState(deviceId, state) {
  const query = `
    UPDATE devices
    SET state = $2, updated_at = NOW()
    WHERE id = $1
  `;
  await db.query(query, [deviceId, state]);
}

module.exports = {
  getDeviceById,
  updateDeviceFCMToken,
  getDeviceByIMEI,
  getDevicesByDealer,
  getDevicesByCustomer,
  updateDeviceState,
};
