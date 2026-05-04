const db = require('../../config/database');
const logger = require('../../utils/logger');

const DEVICE_STATES = {
  ENROLLED: 'enrolled',
  ACTIVE: 'active',
  LOCKED: 'locked',
  UNLOCKED: 'unlocked',
  STOLEN: 'stolen',
  DISABLED: 'disabled',
  DECOUPLED: 'decoupled',
  PENDING_LOCK: 'pending_lock',
  PENDING_UNLOCK: 'pending_unlock',
};

const EMI_STATES = {
  PENDING: 'pending',
  PAID: 'paid',
  OVERDUE: 'overdue',
  DEFAULTED: 'defaulted',
  PARTIALLY_PAID: 'partially_paid',
};

const STATE_TRANSITIONS = {
  [DEVICE_STATES.ENROLLED]: [DEVICE_STATES.ACTIVE, DEVICE_STATES.DISABLED, DEVICE_STATES.DECOUPLED],
  [DEVICE_STATES.ACTIVE]: [DEVICE_STATES.LOCKED, DEVICE_STATES.STOLEN, DEVICE_STATES.DECOUPLED, DEVICE_STATES.DISABLED],
  [DEVICE_STATES.LOCKED]: [DEVICE_STATES.UNLOCKED, DEVICE_STATES.STOLEN, DEVICE_STATES.DECOUPLED],
  [DEVICE_STATES.UNLOCKED]: [DEVICE_STATES.LOCKED, DEVICE_STATES.STOLEN, DEVICE_STATES.DECOUPLED, DEVICE_STATES.ACTIVE],
  [DEVICE_STATES.STOLEN]: [DEVICE_STATES.ACTIVE, DEVICE_STATES.LOCKED, DEVICE_STATES.DECOUPLED],
  [DEVICE_STATES.DISABLED]: [DEVICE_STATES.ACTIVE, DEVICE_STATES.DECOUPLED],
  [DEVICE_STATES.DECOUPLED]: [],
  [DEVICE_STATES.PENDING_LOCK]: [DEVICE_STATES.LOCKED, DEVICE_STATES.ACTIVE],
  [DEVICE_STATES.PENDING_UNLOCK]: [DEVICE_STATES.UNLOCKED, DEVICE_STATES.LOCKED],
};

const EMI_STATE_TRANSITIONS = {
  [EMI_STATES.PENDING]: [EMI_STATES.PAID, EMI_STATES.OVERDUE, EMI_STATES.PARTIALLY_PAID],
  [EMI_STATES.PARTIALLY_PAID]: [EMI_STATES.PAID, EMI_STATES.OVERDUE],
  [EMI_STATES.OVERDUE]: [EMI_STATES.PAID, EMI_STATES.DEFAULTED],
  [EMI_STATES.PAID]: [EMI_STATES.PENDING],
  [EMI_STATES.DEFAULTED]: [EMI_STATES.PAID],
};

function isValidDeviceTransition(fromState, toState) {
  const allowedTransitions = STATE_TRANSITIONS[fromState];
  return allowedTransitions && allowedTransitions.includes(toState);
}

function isValidEmiTransition(fromState, toState) {
  const allowedTransitions = EMI_STATE_TRANSITIONS[fromState];
  return allowedTransitions && allowedTransitions.includes(toState);
}

async function transitionDeviceState(deviceId, newState, actor, reason = null, metadata = {}) {
  const currentDevice = await db.query(
    'SELECT id, state, dealer_id FROM devices WHERE id = $1',
    [deviceId]
  );

  if (currentDevice.rows.length === 0) {
    throw new Error('Device not found');
  }

  const currentState = currentDevice.rows[0].state;

  if (!isValidDeviceTransition(currentState, newState)) {
    throw new Error(`Invalid state transition: ${currentState} -> ${newState}`);
  }

  const result = await db.query(
    `UPDATE devices
     SET state = $1, updated_at = NOW()
     WHERE id = $2
     RETURNING *`,
    [newState, deviceId]
  );

  await logStateTransition({
    entityType: 'device',
    entityId: deviceId,
    fromState: currentState,
    toState: newState,
    actor,
    reason,
    metadata,
  });

  logger.info(`Device state transition: ${deviceId} ${currentState} -> ${newState}`, {
    actor,
    reason,
  });

  return result.rows[0];
}

async function transitionEmiState(emiId, newState, actor, paymentId = null, metadata = {}) {
  const currentEmi = await db.query(
    'SELECT id, status FROM emi_schedules WHERE id = $1',
    [emiId]
  );

  if (currentEmi.rows.length === 0) {
    throw new Error('EMI schedule not found');
  }

  const currentState = currentEmi.rows[0].status;

  if (!isValidEmiTransition(currentState, newState)) {
    throw new Error(`Invalid EMI state transition: ${currentState} -> ${newState}`);
  }

  const result = await db.query(
    `UPDATE emi_schedules
     SET status = $1, updated_at = NOW()
     WHERE id = $2
     RETURNING *`,
    [newState, emiId]
  );

  await logStateTransition({
    entityType: 'emi',
    entityId: emiId,
    fromState: currentState,
    toState: newState,
    actor,
    paymentId,
    metadata,
  });

  logger.info(`EMI state transition: ${emiId} ${currentState} -> ${newState}`, {
    actor,
    paymentId,
  });

  return result.rows[0];
}

async function logStateTransition({ entityType, entityId, fromState, toState, actor, reason, paymentId, metadata }) {
  try {
    await db.query(
      `INSERT INTO state_transitions (entity_type, entity_id, from_state, to_state, actor, reason, payment_id, metadata, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
      [entityType, entityId, fromState, toState, actor, reason, paymentId, JSON.stringify(metadata)]
    );
  } catch (error) {
    logger.error('Failed to log state transition:', error);
  }
}

async function getDeviceStateHistory(deviceId, { limit = 50, offset = 0 } = {}) {
  const result = await db.query(
    `SELECT * FROM state_transitions
     WHERE entity_type = 'device' AND entity_id = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [deviceId, limit, offset]
  );

  return result.rows;
}

async function getEmiStateHistory(emiId, { limit = 50, offset = 0 } = {}) {
  const result = await db.query(
    `SELECT * FROM state_transitions
     WHERE entity_type = 'emi' AND entity_id = $1
     ORDER BY created_at DESC
     LIMIT $2 OFFSET $3`,
    [emiId, limit, offset]
  );

  return result.rows;
}

module.exports = {
  DEVICE_STATES,
  EMI_STATES,
  STATE_TRANSITIONS,
  EMI_STATE_TRANSITIONS,
  isValidDeviceTransition,
  isValidEmiTransition,
  transitionDeviceState,
  transitionEmiState,
  getDeviceStateHistory,
  getEmiStateHistory,
};