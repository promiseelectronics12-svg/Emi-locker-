-- Migration 106: Distributed encrypted evidence vault index
-- Customer photos (NID + face) are NEVER stored on this server.
-- They are encrypted with a split key and stored on dealer/reseller Google Drive.
-- The server holds only: Key Fragment A + a manifest of where copies exist.
-- Neither dealer alone nor server alone can decrypt. Both must cooperate.
--
-- Split key model:
--   Key A  = stored here (server) — encrypted, only released via authorized access flow
--   Key B  = stored alongside encrypted photo in dealer's Google Drive app-data folder
--   Key C  = stored on reseller device (backup copy)
--   Decryption requires A + B + C

CREATE TABLE IF NOT EXISTS evidence_vault_index (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  nid_hash         TEXT        NOT NULL,
  device_id        UUID        REFERENCES devices(id) ON DELETE SET NULL,
  evidence_type    TEXT        NOT NULL CHECK (evidence_type IN (
                                 'NID_FRONT',    -- front of national ID card
                                 'NID_BACK',     -- back of national ID card
                                 'FACE_PHOTO'    -- customer face photo at enrollment
                               )),
  key_a_ref        TEXT        NOT NULL,  -- reference to encrypted Key A in the server key store
  photo_hash       TEXT        NOT NULL,  -- SHA-256 of original unencrypted photo (integrity check)
  dealer_seed_id   TEXT        NOT NULL,  -- Google Drive folder ID / dealer user ID holding the copy
  reseller_seed_id TEXT        NOT NULL,  -- reseller device/user ID holding the backup copy
  enrolled_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at       TIMESTAMPTZ             -- set when customer requests deletion after EMI completion
);

-- Multi-party evidence access log — permanent and tamper-evident.
-- Every access is logged with who, why, and when — legally required.
-- Customer is notified by SMS after every access (transparency principle).
CREATE TABLE IF NOT EXISTS evidence_access_log (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  evidence_id           UUID        NOT NULL REFERENCES evidence_vault_index(id),
  requested_by          UUID        NOT NULL REFERENCES users(id),
  approved_by_1         UUID        REFERENCES users(id),   -- first admin approval
  approved_by_2         UUID        REFERENCES users(id),   -- second admin approval (required)
  key_holder_authorized BOOLEAN     NOT NULL DEFAULT FALSE,  -- dealer/reseller authorized key release
  access_reason         TEXT        NOT NULL,
  case_reference        TEXT,
  access_granted        BOOLEAN     NOT NULL DEFAULT FALSE,
  accessed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  session_expires       TIMESTAMPTZ,  -- 30-minute view window from grant time
  customer_notified     BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_evidence_vault_nid_hash      ON evidence_vault_index(nid_hash);
CREATE INDEX IF NOT EXISTS idx_evidence_vault_device        ON evidence_vault_index(device_id);
CREATE INDEX IF NOT EXISTS idx_evidence_vault_active        ON evidence_vault_index(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_evidence_access_log_evidence ON evidence_access_log(evidence_id);
CREATE INDEX IF NOT EXISTS idx_evidence_access_log_pending  ON evidence_access_log(access_granted) WHERE access_granted = FALSE;
