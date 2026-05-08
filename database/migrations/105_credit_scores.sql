-- Migration 105: Customer credit score network
-- NID-based credit history that works across all dealers on the platform.
-- Trade practice protection: the profile never reveals which dealer sold a device.
-- Cross-dealer lookup returns score + tier only — no business-sensitive details.
-- NID numbers are NEVER stored raw — SHA-256 hash only, used as the lookup key.

CREATE TABLE IF NOT EXISTS customer_credit_profiles (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nid_hash              TEXT        NOT NULL UNIQUE,  -- SHA-256 of NID number
  score                 INTEGER     NOT NULL DEFAULT 500 CHECK (score BETWEEN 0 AND 1000),
  tier                  TEXT        NOT NULL DEFAULT 'BRONZE'
                                    CHECK (tier IN ('GOLD', 'SILVER', 'BRONZE', 'RED', 'BLACKLISTED')),
  member_since          DATE        NOT NULL DEFAULT CURRENT_DATE,
  devices_completed     INTEGER     NOT NULL DEFAULT 0,  -- fully paid-off devices
  installments_paid     INTEGER     NOT NULL DEFAULT 0,
  installments_late     INTEGER     NOT NULL DEFAULT 0,  -- paid but late (1-30 days)
  installments_missed   INTEGER     NOT NULL DEFAULT 0,  -- never paid
  fraud_flags           INTEGER     NOT NULL DEFAULT 0,
  sim_stability         TEXT        NOT NULL DEFAULT 'UNKNOWN'
                                    CHECK (sim_stability IN ('HIGH', 'MEDIUM', 'LOW', 'UNKNOWN')),
  last_activity_month   TEXT,       -- 'YYYY-MM' format — no exact date (privacy)
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE customer_credit_profiles IS
  'Cross-dealer customer credit scores. NID hash is the only identifier. '
  'No dealer_id, device_id, or purchase info is stored here — trade practice protected.';

-- Score change events — permanent audit trail of why a score changed.
-- No dealer_id or device_id — these events are intentionally anonymous.
CREATE TABLE IF NOT EXISTS credit_score_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nid_hash     TEXT        NOT NULL,
  event_type   TEXT        NOT NULL CHECK (event_type IN (
                             'ON_TIME_PAYMENT',    -- +50
                             'LATE_PAYMENT',       -- -30
                             'MISSED_PAYMENT',     -- -60
                             'DEVICE_COMPLETED',   -- +100 (all EMIs paid)
                             'FRAUD_CONFIRMED',    -- -600
                             'SIM_CHANGE',         -- -40
                             'ANOMALY_DETECTED',   -- -25
                             'SIM_STABILITY_HIGH', -- +30 (same number 6+ months)
                             'MANUAL_ADJUSTMENT'   -- admin override
                           )),
  score_delta  INTEGER     NOT NULL,
  score_after  INTEGER     NOT NULL,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Internal fraud blacklist — shared across dealer network, never made public.
-- Only stores a case reference number, not the actual evidence.
-- Dealers see "BLACKLISTED — contact reseller for details" when a match is found.
CREATE TABLE IF NOT EXISTS fraud_blacklist (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nid_hash     TEXT        NOT NULL UNIQUE,
  reason       TEXT        NOT NULL,
  evidence_ref TEXT,       -- case reference only (actual evidence in evidence_vault)
  reported_by  UUID        REFERENCES users(id),
  reported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  active       BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_credit_profiles_nid_hash  ON customer_credit_profiles(nid_hash);
CREATE INDEX IF NOT EXISTS idx_credit_profiles_tier      ON customer_credit_profiles(tier);
CREATE INDEX IF NOT EXISTS idx_credit_score_events_hash  ON credit_score_events(nid_hash);
CREATE INDEX IF NOT EXISTS idx_fraud_blacklist_nid_hash  ON fraud_blacklist(nid_hash);
CREATE INDEX IF NOT EXISTS idx_fraud_blacklist_active    ON fraud_blacklist(active) WHERE active = TRUE;
