const db = require('../../config/database');

async function insertDeliveryLog({ deviceId, commandNonce, commandType, fcmResult, amapiResult, pautResult }) {
  await db.query(
    `INSERT INTO lock_delivery_log 
       (device_id, command_nonce, command_type, fcm_result, amapi_result, paut_result, created_at)
     VALUES ($1, $2, $3, $4, $5, $6, NOW())`,
    [
      deviceId,
      commandNonce,
      commandType,
      JSON.stringify(fcmResult),
      JSON.stringify(amapiResult),
      JSON.stringify(pautResult)
    ]
  );
}

async function getDeviceDeliveryInfo(deviceId) {
  const result = await db.query(
    `SELECT fcm_token, amapi_device_name, imei FROM devices WHERE id = $1`,
    [deviceId]
  );
  return result.rows[0] || null;
}

module.exports = { insertDeliveryLog, getDeviceDeliveryInfo };
