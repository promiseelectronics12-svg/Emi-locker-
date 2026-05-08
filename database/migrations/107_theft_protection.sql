-- Migration 107: Anti-theft silent witness captures
-- When theft is suspected (factory reset attempt, 5 wrong codes, or fake shutdown),
-- the device app captures a photo, audio clip, and location.
-- These are stored encrypted on the device/Google Drive — only the metadata is here.
-- Access follows the same multi-party authorization as evidence_vault.

CREATE TABLE IF NOT EXISTS theft_captures (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id    UUID        NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  trigger      TEXT        NOT NULL CHECK (trigger IN (
                             'FAKE_SHUTDOWN',   -- capture taken during fake power-off window
                             'FRP_ATTEMPT',     -- factory reset protection bypass attempt
                             'WRONG_CODE_5X'   -- 5 consecutive wrong unlock code attempts
                           )),
  captured_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  has_photo    BOOLEAN     NOT NULL DEFAULT FALSE,  -- front camera photo captured
  has_audio    BOOLEAN     NOT NULL DEFAULT FALSE,  -- 10-second audio clip captured
  location_lat NUMERIC(10,7),
  location_lon NUMERIC(10,7),
  evidence_ref TEXT        -- reference to encrypted capture stored on device/Drive
);

CREATE INDEX IF NOT EXISTS idx_theft_captures_device  ON theft_captures(device_id);
CREATE INDEX IF NOT EXISTS idx_theft_captures_trigger ON theft_captures(trigger);
