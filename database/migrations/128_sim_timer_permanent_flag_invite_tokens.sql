-- Migration 128: SIM removal timer persistence, permanent event flag,
--               dealer invite token table
--
-- Addresses three security gaps:
--   1. sim_missing_since — SIM removal timestamp on device row so the
--      5-minute lock grace period survives device reboot
--   2. permanent flag on device_history — SIM/phone change records must
--      not be purged by retention jobs
--   3. dealer_invites — server-issued, hashed, single-use, expiring
--      invite tokens replacing open/deep-link signup
--
-- Idempotent-safe.

BEGIN;

-- ── 1. SIM removal timer on devices ──────────────────────────────────────────
-- Set by user app on SIM removal (immediately persisted via heartbeat).
-- Cleared when bound SIM is restored.
-- On boot: if non-null and older than grace period → lock immediately.

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS sim_missing_since TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_devices_sim_missing
  ON devices(sim_missing_since)
  WHERE sim_missing_since IS NOT NULL;

-- ── 2. Permanent flag on device_history ──────────────────────────────────────
-- Retention jobs must skip rows where permanent = true.
-- SIM change events (SIM_UPDATED, SIM_MISMATCH, SIM_BINDING_SET) and
-- phone number changes must be set with permanent = true at write time.

ALTER TABLE device_history
  ADD COLUMN IF NOT EXISTS permanent BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_device_history_permanent
  ON device_history(device_id, created_at DESC)
  WHERE permanent = true;

-- Mark existing SIM-related history rows as permanent retroactively
UPDATE device_history
SET permanent = true
WHERE event_type IN (
  'SIM_UPDATED',
  'SIM_MISMATCH',
  'SIM_BINDING_SET',
  'SIM_CHANGED',
  'SIM_REMOVED',
  'SIM_RESTORED',
  'PHONE_CHANGED',
  'ENROLLED'
)
AND permanent = false;

-- ── 3. dealer_invites table ───────────────────────────────────────────────────
-- token_hash: SHA-256 of the actual invite token (never stored raw)
-- email: locked — account creation must match this email exactly
-- role: dealer or reseller
-- invited_by: admin or reseller who issued the invite
-- reseller_id: if a reseller is scoped, dealer is created under them
-- expires_at: 48h from creation
-- used_at / used_by: set atomically on account creation (prevents reuse)

CREATE TABLE IF NOT EXISTS dealer_invites (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash   CHAR(64)    NOT NULL UNIQUE,
  email        VARCHAR(255) NOT NULL,
  role         VARCHAR(20) NOT NULL DEFAULT 'dealer'
               CHECK (role IN ('dealer', 'reseller')),
  invited_by   UUID        NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  reseller_id  UUID        REFERENCES users(id) ON DELETE SET NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  used_at      TIMESTAMPTZ,
  used_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dealer_invites_email
  ON dealer_invites(email)
  WHERE used_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_dealer_invites_expiry
  ON dealer_invites(expires_at)
  WHERE used_at IS NULL;

COMMIT;
