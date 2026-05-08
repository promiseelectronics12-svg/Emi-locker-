-- Migration 104: Privacy-first location anomaly system
-- Raw GPS history is NEVER stored on the server. Anomaly detection runs on-device.
-- The device sends only alert events — not coordinates. This keeps server storage
-- near zero and makes the system legally defensible against stalking concerns.

CREATE TABLE IF NOT EXISTS location_anomalies (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id        UUID        NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  alert_type       TEXT        NOT NULL CHECK (alert_type IN (
                                 'UNUSUAL_LOCATION',      -- outside all normal zones
                                 'IMPOSSIBLE_TRAVEL',     -- moved faster than physically possible
                                 'NEW_REGION',            -- first time in a new district/division
                                 'RESET_WITH_RELOCATION', -- factory reset attempt + new location
                                 'SIM_CHANGE_RELOCATION', -- SIM change + new location (combined signal)
                                 'EXTENDED_OFFLINE'       -- offline 7+ days while payment is overdue
                               )),
  area_description TEXT,       -- city/district level only — NOT street address (privacy protection)
  confidence       INTEGER     CHECK (confidence BETWEEN 0 AND 100),
  detected_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  dealer_notified  BOOLEAN     NOT NULL DEFAULT FALSE,
  dealer_viewed    BOOLEAN     NOT NULL DEFAULT FALSE,
  -- Single coordinate stored only for authorized reveal requests.
  -- Access to these fields requires a logged reveal request (see location_reveal_log).
  reveal_lat       NUMERIC(10,7),
  reveal_lon       NUMERIC(10,7)
);

-- Every time a dealer or admin requests the exact coordinates of an anomaly,
-- it is logged permanently. This is the audit trail that makes the system
-- legally defensible — every access is traceable to a person and a stated reason.
CREATE TABLE IF NOT EXISTS location_reveal_log (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  anomaly_id      UUID        NOT NULL REFERENCES location_anomalies(id),
  requested_by    UUID        NOT NULL REFERENCES users(id),
  requester_role  TEXT        NOT NULL,
  reason          TEXT        NOT NULL,
  approved_by     UUID        REFERENCES users(id),  -- required for admin-level reveals
  revealed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  session_expires TIMESTAMPTZ NOT NULL               -- 30-minute view window
);

CREATE INDEX IF NOT EXISTS idx_location_anomalies_device      ON location_anomalies(device_id);
CREATE INDEX IF NOT EXISTS idx_location_anomalies_unnotified  ON location_anomalies(dealer_notified) WHERE dealer_notified = FALSE;
CREATE INDEX IF NOT EXISTS idx_location_reveal_log_anomaly    ON location_reveal_log(anomaly_id);
