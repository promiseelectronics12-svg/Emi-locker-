-- Migration 117: add tier to key_requests
-- Reseller specifies which tier they want when requesting keys from admin.
-- Admin approves with that tier — no override.

ALTER TABLE key_requests
  ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'standard'
    CHECK (tier IN ('standard', 'premium', 'vip'));
