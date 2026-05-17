-- Migration 129: NID HMAC upgrade, device behavior profile table
--
-- 1. NID hashing upgrade:
--    enrollments.nid_hash (plain SHA-256, low-entropy NID input) is
--    insufficient. Add nid_hmac (HMAC-SHA256 keyed with NID_PLATFORM_SECRET)
--    and a version column so legacy records are distinguished from new ones.
--    Backend writes HMAC for all new enrollments. Legacy records stay as v1.
--
-- 2. device_profiles table:
--    Stores learned behavior patterns and adaptive alert state per device.
--    Not linked to assignment — behavior profile is device-level, not
--    customer-level (the device learns its environment, not the owner).
--
-- Idempotent-safe.

BEGIN;

-- ── 1. NID HMAC on enrollments ────────────────────────────────────────────────
-- nid_hmac: HMAC-SHA256(NID_PLATFORM_SECRET, normalize(nid))
--   normalize = strip whitespace, uppercase
-- nid_hash_version: 1 = legacy SHA-256 (weak, existing rows), 2 = HMAC-SHA256
-- Raw NID is never stored. If NID is needed for lookup, recompute HMAC at query.

ALTER TABLE enrollments
  ADD COLUMN IF NOT EXISTS nid_hmac         CHAR(64),
  ADD COLUMN IF NOT EXISTS nid_hash_version SMALLINT NOT NULL DEFAULT 1;

-- Existing rows have SHA-256 in nid_hash (version 1) — mark them explicitly
UPDATE enrollments
SET nid_hash_version = 1
WHERE nid_hash_version = 1 AND nid_hash IS NOT NULL;

-- Note: nid_hmac will be NULL for legacy rows. When a customer re-enrolls,
-- backend writes nid_hmac + sets nid_hash_version = 2 for that record.
-- nid_hash (old column) is retained for audit but no longer written by new code.

CREATE INDEX IF NOT EXISTS idx_enrollments_nid_hmac
  ON enrollments(nid_hmac)
  WHERE nid_hmac IS NOT NULL;

-- ── 2. device_profiles table ─────────────────────────────────────────────────
-- Stores adaptive monitoring state. One row per device, created at enrollment.
-- behavior_profile JSONB structure (written by user app, validated by backend):
-- {
--   "home_lat": float, "home_lng": float, "home_radius_m": int,
--   "work_lat": float, "work_lng": float, "work_radius_m": int,
--   "normal_wakeup_hour": int,       // 0-23
--   "normal_sleep_hour": int,        // 0-23
--   "normal_reboot_frequency": int,  // per week
--   "normal_sim_stable": bool,       // false if SIM changes are routine
--   "normal_charge_start_hour": int,
--   "normal_charge_end_hour": int
-- }

CREATE TABLE IF NOT EXISTS device_profiles (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id             UUID        NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,
  learning_mode_ends_at TIMESTAMPTZ,
  behavior_profile      JSONB       NOT NULL DEFAULT '{}',
  alert_sensitivity     VARCHAR(10) NOT NULL DEFAULT 'normal'
                        CHECK (alert_sensitivity IN ('low', 'normal', 'high')),
  current_mode          VARCHAR(20) NOT NULL DEFAULT 'subconscious'
                        CHECK (current_mode IN (
                          'learning', 'subconscious', 'alert', 'locked', 'fraud'
                        )),
  mode_changed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Backfill: create a profile row for every existing enrolled device
INSERT INTO device_profiles (device_id, current_mode, learning_mode_ends_at)
SELECT
  d.id,
  CASE
    WHEN d.enrolled_at > NOW() - INTERVAL '30 days' THEN 'learning'
    ELSE 'subconscious'
  END,
  CASE
    WHEN d.enrolled_at > NOW() - INTERVAL '30 days'
    THEN d.enrolled_at + INTERVAL '30 days'
    ELSE NULL
  END
FROM devices d
WHERE d.status NOT IN ('pending', 'decommissioned')
  AND NOT EXISTS (
    SELECT 1 FROM device_profiles dp WHERE dp.device_id = d.id
  );

COMMIT;
