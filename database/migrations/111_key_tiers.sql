-- Migration 111: key tiers + dealer quotas
-- Adds a tier column to activation_keys (standard / premium / vip).
-- Adds per-tier quota columns to dealers so resellers can cap how many
-- keys of each type a dealer may use.

ALTER TABLE activation_keys
  ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'standard'
    CHECK (tier IN ('standard', 'premium', 'vip'));

CREATE INDEX IF NOT EXISTS idx_activation_keys_tier ON activation_keys(tier);

ALTER TABLE dealers
  ADD COLUMN IF NOT EXISTS quota_standard  INTEGER NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS quota_premium   INTEGER NOT NULL DEFAULT 200,
  ADD COLUMN IF NOT EXISTS quota_vip       INTEGER NOT NULL DEFAULT 50;
