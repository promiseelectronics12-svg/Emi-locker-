const db = require('../../config/database');
const fcmService = require('./fcm.service');
const logger = require('../../utils/logger');

const DEFAULT_TITLES = {
  sim_removed: 'SIM Removed',
  device_locked: 'Device Locked',
  device_unlocked: 'Device Unlocked',
  app_tamper: 'Tamper Detected',
  shutdown_detected: 'Shutdown Detected',
  payment_confirmed: 'Payment Confirmed',
  advance_payment: 'Advance Payment Confirmed',
  app_removed_suspected: 'App Removal Suspected'
};

function compact(value) {
  return Object.fromEntries(
    Object.entries(value || {}).filter(([, v]) => v !== undefined && v !== null)
  );
}

function deviceLabel(device = {}) {
  return device.device_name || [device.brand, device.model].filter(Boolean).join(' ') || device.imei || 'Device';
}

async function getDealerToken(dealerId) {
  if (!dealerId) return null;
  const result = await db.query(
    `SELECT id, fcm_token FROM dealers WHERE id = $1 LIMIT 1`,
    [dealerId]
  );
  return result.rows[0] || null;
}

async function sendToDealer(dealerId, type, body, data = {}, title = null) {
  const dealer = await getDealerToken(dealerId);
  if (!dealer?.fcm_token) {
    logger.debug('Dealer FCM token missing; push skipped', { dealerId, type });
    return { success: false, skipped: true, reason: 'NO_DEALER_FCM_TOKEN' };
  }

  const payload = compact({
    type,
    title: title || DEFAULT_TITLES[type] || 'EMI Locker Alert',
    body,
    dealerId,
    timestamp: new Date().toISOString(),
    ...data
  });

  const result = await fcmService.sendToDevice(dealer.fcm_token, payload);
  if (result.invalidToken) {
    await db.query(
      `UPDATE dealers SET fcm_token = NULL, updated_at = NOW() WHERE id = $1`,
      [dealerId]
    );
  }

  if (!result.success) {
    logger.warn('Dealer FCM push failed', {
      dealerId,
      type,
      code: result.code,
      error: result.error,
      invalidToken: result.invalidToken
    });
  }

  return result;
}

function sendToDealerSafe(dealerId, type, body, data = {}, title = null) {
  return sendToDealer(dealerId, type, body, data, title).catch((error) => {
    logger.warn('Dealer notification send failed', {
      dealerId,
      type,
      error: error.message
    });
    return { success: false, error: error.message };
  });
}

function notifyDeviceLocked(device = {}, reason = null) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  const lockReason = reason || device.lock_reason || 'LOCKED';
  return sendToDealerSafe(
    device.dealer_id,
    'device_locked',
    `${label} is locked${lockReason ? ` (${lockReason})` : ''}.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      lockLevel: device.lock_level,
      reason: lockReason
    }
  );
}

function notifyDeviceUnlocked(device = {}, graceHours = null) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'device_unlocked',
    graceHours ? `${label} is unlocked for ${graceHours} hours.` : `${label} is unlocked.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      graceHours
    }
  );
}

function notifySimRemoved(device = {}, details = {}) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'sim_removed',
    details.wrongSim
      ? `${label} reported a different SIM.`
      : `${label} reported the bound SIM missing.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      oldPhone: details.oldPhone,
      newPhone: details.newPhone,
      wrongSim: details.wrongSim === true
    }
  );
}

function notifyAppTamper(device = {}, reason = 'APP_TAMPER') {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'app_tamper',
    `${label} reported app protection tamper: ${reason}.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      reason
    }
  );
}

function notifyAppRemovedSuspected(device = {}, reason = 'FCM_TOKEN_INVALID') {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'app_removed_suspected',
    `${label} may have removed or disabled the user app.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      reason
    }
  );
}

function notifyShutdownDetected(device = {}, location = {}) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'shutdown_detected',
    `${label} reported a shutdown event.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      lat: location.lat,
      lng: location.lng
    }
  );
}

function notifyPaymentConfirmed(device = {}, payment = {}) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  const amount = payment.amount ? `${payment.amount} BDT` : 'Payment';
  return sendToDealerSafe(
    device.dealer_id,
    'payment_confirmed',
    `${amount} confirmed for ${label}.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      paymentId: payment.paymentId || payment.id,
      amount: payment.amount,
      installmentNumber: payment.installmentNumber || payment.installment_number,
      isFinalPayment: payment.isFinalPayment === true
    }
  );
}

function notifyAdvancePayment(device = {}, payment = {}) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  return sendToDealerSafe(
    device.dealer_id,
    'advance_payment',
    `Advance payment confirmed for ${label}.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      paymentId: payment.paymentId || payment.id,
      amount: payment.amount,
      installmentNumber: payment.installmentNumber || payment.installment_number
    }
  );
}

function notifyRiskThreshold(device = {}, riskScore, signalBreakdown = {}, windowExpiresAt = null) {
  if (!device.dealer_id) return Promise.resolve({ success: false, skipped: true });
  const label = deviceLabel(device);
  const signalNames = Object.keys(signalBreakdown).join(', ');
  return sendToDealerSafe(
    device.dealer_id,
    'risk_score_threshold',
    `${label} is at risk score ${riskScore}. Auto-lock in 2 hours if not resolved.`,
    {
      deviceId: device.id,
      deviceName: label,
      imei: device.imei,
      riskScore,
      signalNames,
      windowExpiresAt,
    },
    'Risk Threshold Reached'
  );
}

module.exports = {
  sendToDealer,
  sendToDealerSafe,
  notifyDeviceLocked,
  notifyDeviceUnlocked,
  notifySimRemoved,
  notifyAppTamper,
  notifyAppRemovedSuspected,
  notifyShutdownDetected,
  notifyPaymentConfirmed,
  notifyAdvancePayment,
  notifyRiskThreshold,
};
