-- Migration: 010_paut_tokens.sql
-- Description: PAUT (Pre-Authorized Unlock Tokens) for device actions
-- token_hash is a hashed token value; actual token given to device/user
-- nonce prevents replay attacks; tokens valid only when used=FALSE AND expires_at > NOW()

CREATE TABLE paut_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jti             UUID NOT NULL UNIQUE,
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    imei            TEXT NOT NULL,
    lock_level      TEXT NOT NULL DEFAULT 'FULL_LOCK',
    token_hash      TEXT NOT NULL,
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ NOT NULL,
    used            BOOLEAN NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    revoked         BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_paut_tokens_jti ON paut_tokens (jti);
CREATE INDEX idx_paut_tokens_device_id ON paut_tokens (device_id);
CREATE INDEX idx_paut_tokens_lock_level ON paut_tokens (lock_level);
CREATE INDEX idx_paut_tokens_expires_at ON paut_tokens (expires_at);
CREATE INDEX idx_paut_tokens_used ON paut_tokens (used);
CREATE INDEX idx_paut_tokens_revoked ON paut_tokens (revoked);

-- Composite index for valid (unused, not expired, not revoked) tokens per device
CREATE INDEX idx_paut_tokens_valid
    ON paut_tokens (device_id, lock_level, used, expires_at)
    WHERE used = FALSE AND revoked = FALSE AND expires_at > NOW();

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_paut_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_paut_tokens_updated_at
    BEFORE UPDATE ON paut_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_paut_tokens_updated_at();
