/**
 * SSE (Server-Sent Events) service.
 *
 * Manages all connected clients and provides push functions
 * called from anywhere in the backend when something changes.
 *
 * Single-process safe. If you later run PM2 cluster mode,
 * replace the Map with a Redis pub/sub broadcast.
 */

// clients: Map<userId, { res, role, dealerId? }>
const clients = new Map();

// ── Connection management ────────────────────────────────────────────────────

function addClient(userId, role, res, dealerId = null) {
  clients.set(userId, { res, role, dealerId });
}

function removeClient(userId) {
  clients.delete(userId);
}

function clientCount() {
  return clients.size;
}

// ── Push helpers ─────────────────────────────────────────────────────────────

function _write(res, event, data) {
  try {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  } catch (_) {
    // client disconnected mid-write — ignore
  }
}

/** Push to one specific user */
function pushToUser(userId, event, data) {
  const client = clients.get(String(userId));
  if (client) {
    _write(client.res, event, data);
  } else {
    console.warn(`[SSE] pushToUser: no client for userId=${userId} event=${event} (connected: ${[...clients.keys()].join(',')})`);
  }
}

/** Push to every connected admin */
function pushToAdmins(event, data) {
  for (const [, client] of clients) {
    if (client.role === 'admin') _write(client.res, event, data);
  }
}

/** Push to every connected reseller */
function pushToResellers(event, data) {
  for (const [, client] of clients) {
    if (client.role === 'reseller') _write(client.res, event, data);
  }
}

/** Push to a specific dealer (by dealerId, not userId) */
function pushToDealer(dealerId, event, data) {
  for (const [, client] of clients) {
    if (client.role === 'dealer' && String(client.dealerId) === String(dealerId)) {
      _write(client.res, event, data);
    }
  }
}

/** Push to all admins + all resellers (management roles) */
function pushToManagement(event, data) {
  for (const [, client] of clients) {
    if (client.role === 'admin' || client.role === 'reseller') {
      _write(client.res, event, data);
    }
  }
}

/** Push to everyone connected */
function pushToAll(event, data) {
  for (const [, client] of clients) {
    _write(client.res, event, data);
  }
}

// ── Named event helpers (called from backend modules) ────────────────────────

function emitDeviceLocked(device) {
  pushToManagement('device_locked', {
    deviceId:   device.id,
    deviceName: device.device_name,
    imei:       device.imei,
    lockLevel:  device.lock_level,
    reason:     device.lock_reason,
    lockedAt:   device.locked_at || new Date().toISOString(),
  });
  if (device.dealer_id) {
    pushToDealer(device.dealer_id, 'device_locked', {
      deviceId:   device.id,
      deviceName: device.device_name,
      lockLevel:  device.lock_level,
      reason:     device.lock_reason,
    });
  }
}

function emitDeviceUnlocked(device, graceHours) {
  const payload = {
    deviceId:   device.id,
    deviceName: device.device_name,
    graceHours,
    unlockedAt: new Date().toISOString(),
  };
  pushToManagement('device_unlocked', payload);
  if (device.dealer_id) {
    pushToDealer(device.dealer_id, 'device_unlocked', payload);
  }
}

function emitNewAlert(alert) {
  pushToManagement('new_alert', {
    alertId:    alert.id,
    type:       alert.alert_type || alert.type,
    deviceId:   alert.device_id,
    deviceName: alert.device_name,
    severity:   alert.severity || 'medium',
    createdAt:  alert.created_at || new Date().toISOString(),
  });
}

function emitEnrollmentComplete(device, dealerId) {
  pushToManagement('enrollment_complete', {
    deviceId:   device.id,
    deviceName: device.device_name,
    imei:       device.imei,
    enrolledAt: new Date().toISOString(),
  });
  if (dealerId) {
    pushToDealer(dealerId, 'enrollment_complete', {
      deviceId:   device.id,
      deviceName: device.device_name,
    });
  }
}

function emitGraceExpired(device) {
  const payload = {
    deviceId:   device.id,
    deviceName: device.device_name,
    expiredAt:  new Date().toISOString(),
  };
  pushToManagement('grace_expired', payload);
  if (device.dealer_id) {
    pushToDealer(device.dealer_id, 'grace_expired', payload);
  }
}

function emitPaymentRecorded(deviceId, deviceName, amount) {
  pushToManagement('payment_recorded', { deviceId, deviceName, amount, recordedAt: new Date().toISOString() });
}

function emitKeyRequested(resellerId, resellerName, requestId, quantity, tier) {
  pushToAdmins('key_requested', {
    requestId,
    resellerId,
    resellerName: resellerName || 'Reseller',
    quantity,
    tier,
    requestedAt: new Date().toISOString(),
  });
}

function emitKeyRequestApproved(resellerId, quantity, tier) {
  pushToUser(resellerId, 'key_request_approved', {
    quantity,
    tier,
    approvedAt: new Date().toISOString(),
  });
}

module.exports = {
  addClient,
  removeClient,
  clientCount,
  pushToUser,
  pushToAdmins,
  pushToResellers,
  pushToDealer,
  pushToManagement,
  pushToAll,
  emitDeviceLocked,
  emitDeviceUnlocked,
  emitNewAlert,
  emitEnrollmentComplete,
  emitGraceExpired,
  emitPaymentRecorded,
  emitKeyRequested,
  emitKeyRequestApproved,
};
