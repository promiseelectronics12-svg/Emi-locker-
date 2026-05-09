-- Migration 118: device_events table for shutdown/boot GPS tracking
CREATE TABLE IF NOT EXISTS device_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  type        TEXT NOT NULL,
  lat         NUMERIC(10, 7),
  lng         NUMERIC(10, 7),
  recorded_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_events_device_id ON device_events(device_id);
CREATE INDEX IF NOT EXISTS idx_device_events_type ON device_events(type);
CREATE INDEX IF NOT EXISTS idx_device_events_created_at ON device_events(created_at DESC);
