-- Migration 114: per-tier key quota on resellers
-- Tracks how many keys of each tier the admin has approved for a reseller.
-- Keys are generated fresh at assign-time (reseller → dealer), not at approval.

ALTER TABLE resellers
  ADD COLUMN IF NOT EXISTS quota_standard INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS quota_premium  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS quota_vip      INTEGER NOT NULL DEFAULT 0;
