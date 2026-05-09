-- Migration 119: add tier to enrollments so key consumption knows which tier to deduct
ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'standard'
  CHECK (tier IN ('standard', 'premium', 'vip'));
