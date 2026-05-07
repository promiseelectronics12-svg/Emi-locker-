-- Migration 100: Dealer device settings
-- Stores dealer-configurable per-device offline and lock-screen parameters.
-- The server enforces hard limits (grace floor 24h, check-in floor 60 min).

CREATE TABLE IF NOT EXISTS dealer_device_settings (
  id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id                UUID         NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  dealer_id                UUID         NOT NULL,

  -- Offline resilience controls
  offline_grace_hours      INTEGER      NOT NULL DEFAULT 72
                           CHECK (offline_grace_hours BETWEEN 24 AND 168),
  warning_threshold_hours  INTEGER      NOT NULL DEFAULT 12
                           CHECK (warning_threshold_hours BETWEEN 1 AND 48),
  checkin_interval_minutes INTEGER      NOT NULL DEFAULT 360
                           CHECK (checkin_interval_minutes BETWEEN 60 AND 1440),

  -- Lock screen branding (shown on customer's locked device)
  lock_screen_message      TEXT         CHECK (char_length(lock_screen_message) <= 200),
  lock_screen_dealer_name  TEXT         CHECK (char_length(lock_screen_dealer_name) <= 80),
  lock_screen_dealer_phone TEXT         CHECK (char_length(lock_screen_dealer_phone) <= 20),

  -- Lock behaviour
  default_lock_level       TEXT         NOT NULL DEFAULT 'FULL'
                           CHECK (default_lock_level IN ('SOFT', 'FULL')),

  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  UNIQUE (device_id)
);

CREATE INDEX IF NOT EXISTS idx_dealer_device_settings_dealer
  ON dealer_device_settings(dealer_id);

-- Dealer-level defaults (applied to new enrollments if no per-device row exists)
CREATE TABLE IF NOT EXISTS dealer_defaults (
  dealer_id                UUID         PRIMARY KEY,
  offline_grace_hours      INTEGER      NOT NULL DEFAULT 72
                           CHECK (offline_grace_hours BETWEEN 24 AND 168),
  warning_threshold_hours  INTEGER      NOT NULL DEFAULT 12,
  checkin_interval_minutes INTEGER      NOT NULL DEFAULT 360
                           CHECK (checkin_interval_minutes BETWEEN 60 AND 1440),
  default_lock_level       TEXT         NOT NULL DEFAULT 'FULL'
                           CHECK (default_lock_level IN ('SOFT', 'FULL')),
  lock_screen_dealer_name  TEXT         CHECK (char_length(lock_screen_dealer_name) <= 80),
  lock_screen_dealer_phone TEXT         CHECK (char_length(lock_screen_dealer_phone) <= 20),
  lock_screen_message      TEXT         CHECK (char_length(lock_screen_message) <= 200),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
