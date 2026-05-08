-- Migration 108: Distributed customer profile seed index
-- Customer profiles live in Google Drive (dealer/reseller nodes), not on this server.
-- This table tracks WHO holds a copy of each customer's profile so the app knows
-- which Drive to fetch from without hitting the server for the actual data.
-- Server is coordinator only — 90% of profile lookups are served by reseller cache.

CREATE TABLE IF NOT EXISTS profile_seed_index (
  nid_hash        TEXT        NOT NULL,
  seed_type       TEXT        NOT NULL CHECK (seed_type IN ('DEALER_DRIVE', 'RESELLER_DRIVE')),
  seed_holder_id  UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (nid_hash, seed_type, seed_holder_id)
);

CREATE INDEX IF NOT EXISTS idx_profile_seeds_nid_hash ON profile_seed_index(nid_hash);
CREATE INDEX IF NOT EXISTS idx_profile_seeds_holder   ON profile_seed_index(seed_holder_id);
