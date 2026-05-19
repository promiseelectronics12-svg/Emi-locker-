-- Migration 131: Risk Engine Tables
-- Three tables for the compound-risk auto-lock system.
-- Lock rule: overdue_emi && risk_score >= 6 && dealer_notification_window_expired (2h).
-- Single tamper signal never auto-locks. Every evaluation is fully audited.

CREATE TABLE IF NOT EXISTS device_risk_scores (
  device_id     UUID PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  total_score   INTEGER      NOT NULL DEFAULT 0,
  signals       JSONB        NOT NULL DEFAULT '{}',
  -- signals shape: { "signal_type": { "weight": N, "since": "ISO8601", "details": {} } }
  dealer_notified_at TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_risk_scores_total ON device_risk_scores(total_score);

-- -----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS risk_signal_log (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   UUID         NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  signal_type VARCHAR(60)  NOT NULL,
  weight      INTEGER      NOT NULL,
  action      VARCHAR(20)  NOT NULL CHECK (action IN ('recorded','escalated','cleared')),
  details     JSONB,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_risk_signal_log_device ON risk_signal_log(device_id, created_at DESC);

-- -----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS auto_lock_decisions (
  id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id           UUID        NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  is_overdue          BOOLEAN     NOT NULL,
  risk_score          INTEGER     NOT NULL,
  signal_breakdown    JSONB       NOT NULL,
  dealer_notified_at  TIMESTAMPTZ,
  window_expires_at   TIMESTAMPTZ,
  window_expired      BOOLEAN     NOT NULL,
  decision            VARCHAR(40) NOT NULL,
  -- 'locked' | 'pending_dealer_window' | 'score_insufficient' | 'not_overdue' | 'already_locked'
  notes               TEXT,
  evaluated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE auto_lock_decisions
  ADD COLUMN IF NOT EXISTS window_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_auto_lock_decisions_device ON auto_lock_decisions(device_id, evaluated_at DESC);
