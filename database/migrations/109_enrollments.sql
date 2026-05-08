-- Migration 109: enrollment table for the new 6-digit token binding flow.
-- A row is created when a dealer starts the wizard and confirmed when the code is verified.

CREATE TABLE IF NOT EXISTS enrollments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id      UUID          NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  dealer_id      UUID          NOT NULL,
  customer_name  VARCHAR(128)  NOT NULL,
  nid_hash       CHAR(64)      NOT NULL,
  phone_number   VARCHAR(20)   NOT NULL,
  brand          VARCHAR(64),
  model          VARCHAR(64),
  imei1          VARCHAR(16)   NOT NULL,
  imei2          VARCHAR(16),
  token_hash     CHAR(64)      NOT NULL,
  status         VARCHAR(20)   NOT NULL DEFAULT 'pending'  CHECK (status IN ('pending','confirmed','expired')),
  expires_at     TIMESTAMPTZ   NOT NULL,
  confirmed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_enrollments_device  ON enrollments(device_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_dealer  ON enrollments(dealer_id);
CREATE INDEX IF NOT EXISTS idx_enrollments_status  ON enrollments(status, expires_at);

-- Add 'pending' to devices.status allowed values if not already present.
-- The check constraint may already include it in newer schemas; this is a no-op if so.
DO $$
BEGIN
  ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_status_check;
  ALTER TABLE devices ADD CONSTRAINT devices_status_check CHECK (
    status IN ('pending','enrolled','active','locked','partial_lock','reminder',
               'decoupled','disabled','suspended')
  );
EXCEPTION WHEN others THEN
  NULL; -- ignore if constraint cannot be altered
END;
$$;
