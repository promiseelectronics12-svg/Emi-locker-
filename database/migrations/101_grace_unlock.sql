-- Migration 101: Grace unlock events
-- Tracks dealer-issued offline grace period unlocks.
-- When a dealer calls the customer and agrees to temporarily unlock their device,
-- they send an SMS OTP that includes a grace period duration. This table logs each event.

CREATE TABLE IF NOT EXISTS grace_unlock_events (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     UUID        NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  dealer_id     UUID        NOT NULL,
  grace_hours   INTEGER     NOT NULL CHECK (grace_hours IN (2, 4, 8, 24)),
  otp_window    BIGINT      NOT NULL,           -- HOTP counter used (timeWindow * 10 + grace_index)
  issued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL,           -- issued_at + grace_hours
  revoked       BOOLEAN     NOT NULL DEFAULT FALSE,
  revoked_at    TIMESTAMPTZ,
  sms_sent_to   TEXT        NOT NULL            -- masked phone, for audit
);

CREATE INDEX IF NOT EXISTS idx_grace_unlock_device  ON grace_unlock_events(device_id);
CREATE INDEX IF NOT EXISTS idx_grace_unlock_dealer  ON grace_unlock_events(dealer_id);
CREATE INDEX IF NOT EXISTS idx_grace_unlock_expires ON grace_unlock_events(expires_at);

-- Convenience view: active (non-expired, non-revoked) grace unlocks
CREATE OR REPLACE VIEW active_grace_unlocks AS
  SELECT *
  FROM   grace_unlock_events
  WHERE  revoked    = FALSE
    AND  expires_at > NOW();
