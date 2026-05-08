-- Migration 103: SIM change detection events
-- When the customer app detects a SIM swap, it sends a hashed event to the server.
-- SIM numbers are NEVER stored raw — SHA-256 hash only, for comparison purposes.
-- Combined with a simultaneous location change, this is a high-confidence fraud signal.

CREATE TABLE IF NOT EXISTS sim_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id    UUID        NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  event_type   TEXT        NOT NULL CHECK (event_type IN (
                             'SIM_CHANGED',   -- new SIM inserted
                             'SIM_REMOVED',   -- SIM removed (no replacement yet)
                             'SIM_RESTORED'   -- original SIM re-inserted
                           )),
  old_sim_hash TEXT,       -- SHA-256 of old SIM number — nullable (first time or unknown)
  new_sim_hash TEXT,       -- SHA-256 of new SIM number — nullable for SIM_REMOVED
  detected_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  location_lat NUMERIC(10,7),  -- device location at time of SIM change (if available)
  location_lon NUMERIC(10,7),
  notified     BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_sim_events_device     ON sim_events(device_id);
CREATE INDEX IF NOT EXISTS idx_sim_events_unnotified ON sim_events(notified) WHERE notified = FALSE;
CREATE INDEX IF NOT EXISTS idx_sim_events_detected   ON sim_events(detected_at DESC);
