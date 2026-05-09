-- Migration 110: trusted_devices
-- Stores per-device trust records for dealers/resellers.
-- A device is trusted after the user verifies an email OTP on first login.
-- Trusted devices skip OTP on subsequent logins (password only).

CREATE TABLE IF NOT EXISTS trusted_devices (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_fingerprint  TEXT        NOT NULL,
  device_name         TEXT,
  last_used_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, device_fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_trusted_devices_user ON trusted_devices(user_id);
