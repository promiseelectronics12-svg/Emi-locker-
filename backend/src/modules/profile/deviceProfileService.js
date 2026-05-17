const db = require('../../config/database');
const logger = require('../../utils/logger');

const VALID_MODES = ['learning', 'subconscious', 'alert', 'locked', 'fraud'];
const VALID_SENSITIVITY = ['low', 'normal', 'high'];

/**
 * Returns profile for a device, creating a default one if missing.
 */
async function getOrCreate(deviceId) {
  const result = await db.query(
    `SELECT * FROM device_profiles WHERE device_id = $1`,
    [deviceId]
  );
  if (result.rows[0]) return result.rows[0];

  // Create default — use learning mode if device enrolled within last 30 days
  const deviceRow = await db.query(
    `SELECT enrolled_at FROM devices WHERE id = $1`,
    [deviceId]
  );
  const enrolledAt = deviceRow.rows[0]?.enrolled_at;
  const inLearning = enrolledAt && new Date(enrolledAt) > new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

  const created = await db.query(
    `INSERT INTO device_profiles (device_id, current_mode, learning_mode_ends_at)
     VALUES ($1, $2, $3)
     ON CONFLICT (device_id) DO UPDATE SET updated_at = NOW()
     RETURNING *`,
    [
      deviceId,
      inLearning ? 'learning' : 'subconscious',
      inLearning && enrolledAt ? new Date(new Date(enrolledAt).getTime() + 30 * 24 * 60 * 60 * 1000) : null
    ]
  );
  return created.rows[0];
}

/**
 * Transitions device to a new monitoring mode.
 * Higher-severity modes (locked/fraud) cannot be downgraded by this function
 * — those are controlled by lock/fraud services directly.
 */
async function updateMode(deviceId, mode) {
  if (!VALID_MODES.includes(mode)) throw new Error(`Invalid mode: ${mode}`);

  const result = await db.query(
    `UPDATE device_profiles
     SET current_mode = $2, mode_changed_at = NOW(), updated_at = NOW()
     WHERE device_id = $1
     RETURNING current_mode`,
    [deviceId, mode]
  );

  if (!result.rows.length) {
    await getOrCreate(deviceId);
    return updateMode(deviceId, mode);
  }

  logger.info(`Device ${deviceId} mode → ${mode}`);
  return result.rows[0];
}

/**
 * Updates learned behavior fields (partial patch via JSONB merge).
 * Rate-limited in routes to max 1 update/hour per device.
 */
async function updateBehaviorProfile(deviceId, patch) {
  const result = await db.query(
    `UPDATE device_profiles
     SET behavior_profile = behavior_profile || $2::jsonb,
         updated_at = NOW()
     WHERE device_id = $1
     RETURNING behavior_profile`,
    [deviceId, JSON.stringify(patch)]
  );

  if (!result.rows.length) {
    await getOrCreate(deviceId);
    return updateBehaviorProfile(deviceId, patch);
  }

  return result.rows[0].behavior_profile;
}

async function updateSensitivity(deviceId, sensitivity) {
  if (!VALID_SENSITIVITY.includes(sensitivity)) throw new Error(`Invalid sensitivity: ${sensitivity}`);
  await db.query(
    `UPDATE device_profiles SET alert_sensitivity = $2, updated_at = NOW() WHERE device_id = $1`,
    [deviceId, sensitivity]
  );
}

async function isInLearningMode(deviceId) {
  const result = await db.query(
    `SELECT current_mode, learning_mode_ends_at FROM device_profiles WHERE device_id = $1`,
    [deviceId]
  );
  const profile = result.rows[0];
  if (!profile) return false;
  if (profile.current_mode !== 'learning') return false;
  if (profile.learning_mode_ends_at && new Date(profile.learning_mode_ends_at) < new Date()) {
    // Learning period expired — auto-transition to subconscious
    await updateMode(deviceId, 'subconscious');
    return false;
  }
  return true;
}

module.exports = {
  getOrCreate,
  updateMode,
  updateBehaviorProfile,
  updateSensitivity,
  isInLearningMode
};
