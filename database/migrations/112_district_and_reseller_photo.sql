-- Migration 112: Add district field to dealers and resellers for Bangladesh map.
-- Also adds photo_url and nid_drive_file_id to resellers for invite onboarding.

ALTER TABLE dealers
  ADD COLUMN IF NOT EXISTS district VARCHAR(64);

ALTER TABLE resellers
  ADD COLUMN IF NOT EXISTS district        VARCHAR(64),
  ADD COLUMN IF NOT EXISTS photo_url       TEXT,
  ADD COLUMN IF NOT EXISTS nid_drive_file_id TEXT;

CREATE INDEX IF NOT EXISTS idx_dealers_district   ON dealers(district);
CREATE INDEX IF NOT EXISTS idx_resellers_district ON resellers(district);
