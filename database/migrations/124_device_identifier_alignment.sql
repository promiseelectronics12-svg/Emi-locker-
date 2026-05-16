-- Migration 124: align Android pre-registration with dealer IMEI enrollment.
-- Normal Android apps cannot reliably read IMEI, so the user app may identify
-- itself with android_id/device_bound_id before the dealer enters the IMEI.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS android_id TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_bound_id TEXT;

CREATE INDEX IF NOT EXISTS idx_devices_android_id
  ON devices(android_id)
  WHERE android_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_devices_device_bound_id
  ON devices(device_bound_id)
  WHERE device_bound_id IS NOT NULL;
