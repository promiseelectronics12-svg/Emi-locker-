-- Migration: 003_activation_keys.sql
-- Description: Activation keys with HMAC-SHA256 signing
-- key_hash: SHA-256 of the actual key_value (one-way hash, never stored plaintext)
-- hmac_sig: HMAC-SHA256 signature for external verification with HSM key (optional)

-- ENUM for activation key status
CREATE TYPE activation_key_status AS ENUM (
    'available',
    'assigned',
    'activated',
    'expired',
    'revoked',
    'suspended'
);

CREATE TABLE activation_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- key_hash: SHA-256 hash of the actual key (one-way, never stored plaintext)
    -- Application computes hash of provided key and compares to this value
    key_hash        TEXT NOT NULL,
    reseller_id     UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    dealer_id       UUID REFERENCES users(id) ON DELETE SET NULL,
    device_id       UUID REFERENCES devices(id) ON DELETE SET NULL,
    status          activation_key_status NOT NULL DEFAULT 'available',
    expires_at      TIMESTAMPTZ NOT NULL,
    -- hmac_sig: HMAC-SHA256 signature for external verification with HSM key
    -- Can be removed if no external HSM verification is required
    hmac_sig        TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique index on key hash to prevent duplicate keys
CREATE UNIQUE INDEX idx_activation_keys_key_hash ON activation_keys (key_hash);
CREATE INDEX idx_activation_keys_reseller_id ON activation_keys (reseller_id);
CREATE INDEX idx_activation_keys_dealer_id ON activation_keys (dealer_id);
CREATE INDEX idx_activation_keys_device_id ON activation_keys (device_id);
CREATE INDEX idx_activation_keys_status ON activation_keys (status);
CREATE INDEX idx_activation_keys_expires_at ON activation_keys (expires_at);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_activation_keys_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_activation_keys_updated_at
    BEFORE UPDATE ON activation_keys
    FOR EACH ROW
    EXECUTE FUNCTION update_activation_keys_updated_at();
