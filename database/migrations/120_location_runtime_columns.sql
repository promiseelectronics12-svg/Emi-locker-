-- Migration: 120_location_runtime_columns.sql
-- Description: Align live location schema with backend runtime expectations.

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS last_location_lat DECIMAL(10, 8),
  ADD COLUMN IF NOT EXISTS last_location_lng DECIMAL(11, 8),
  ADD COLUMN IF NOT EXISTS last_location_time TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS battery_level INTEGER;

ALTER TABLE location_reports
  ADD COLUMN IF NOT EXISTS recorded_at TIMESTAMPTZ;

UPDATE location_reports
SET recorded_at = COALESCE(recorded_at, timestamp, created_at, NOW())
WHERE recorded_at IS NULL;

UPDATE devices d
SET
  last_location_lat = latest.latitude,
  last_location_lng = latest.longitude,
  last_location_time = latest.timestamp,
  last_location_at = latest.timestamp,
  battery_level = latest.battery_level
FROM (
  SELECT DISTINCT ON (device_id)
    device_id,
    latitude,
    longitude,
    timestamp,
    battery_level
  FROM location_reports
  ORDER BY device_id, timestamp DESC
) latest
WHERE d.id = latest.device_id
  AND (
    d.last_location_lat IS NULL
    OR d.last_location_lng IS NULL
    OR d.last_location_time IS NULL
    OR d.last_location_at IS NULL
  );

CREATE INDEX IF NOT EXISTS idx_devices_last_location_at
  ON devices(last_location_at DESC);

CREATE INDEX IF NOT EXISTS idx_location_reports_recorded_at
  ON location_reports(recorded_at DESC);
