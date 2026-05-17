-- Migration 126: device_history table, fraud_suspected status, device SMS heartbeat columns, location_reports source
-- Idempotent-safe: can be re-run without error.

BEGIN;

-- 1. Replace devices.status CHECK — drop old first so existing 'stolen'
-- rows can be migrated to 'fraud_suspected' before validating the new rule.
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_status_check;

-- 2. Migrate existing 'stolen' rows before adding constraint that excludes 'stolen'
UPDATE devices SET status = 'fraud_suspected' WHERE status = 'stolen';

ALTER TABLE devices ADD CONSTRAINT devices_status_check CHECK (
  status IN (
    'pending',
    'enrolled',
    'active',
    'locked',
    'unlocked',
    'partial_lock',
    'reminder',
    'pending_lock',
    'pending_unlock',
    'pending_decouple',
    'decoupled',
    'disabled',
    'suspended',
    'fraud_suspected'
  )
) NOT VALID;

ALTER TABLE devices VALIDATE CONSTRAINT devices_status_check;

-- 3. New columns on devices (idempotent via IF NOT EXISTS)
ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS registered_phone VARCHAR(20),
  ADD COLUMN IF NOT EXISTS last_sms_heartbeat_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sms_heartbeat_sequence BIGINT DEFAULT 0;

-- 4. Add source column to location_reports (idempotent)
ALTER TABLE location_reports
  ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'gps'
    CHECK (source IN ('gps', 'network', 'sms_heartbeat', 'dealer_reveal'));

-- 5. device_history table (idempotent)
CREATE TABLE IF NOT EXISTS device_history (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id        UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  event_type       VARCHAR(60) NOT NULL,
  actor_type       VARCHAR(20) CHECK (actor_type IN ('system', 'admin', 'dealer', 'device')),
  actor_id         UUID,
  details          JSONB DEFAULT '{}',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_history_device
  ON device_history(device_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_device_history_event_type
  ON device_history(event_type, created_at DESC);

COMMIT;
