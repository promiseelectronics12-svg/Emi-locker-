-- Migration 115: dealer profile fields
-- Adds NID, photo, division, thana for complete dealer identity capture.

ALTER TABLE dealers
  ADD COLUMN IF NOT EXISTS nid       TEXT,
  ADD COLUMN IF NOT EXISTS photo_url TEXT,
  ADD COLUMN IF NOT EXISTS division  TEXT,
  ADD COLUMN IF NOT EXISTS thana     TEXT;
