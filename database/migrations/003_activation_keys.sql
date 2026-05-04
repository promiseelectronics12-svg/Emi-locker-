-- Migration: 003_activation_keys.sql
-- Description: Device activation keys for enrollment

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS activation_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key_code VARCHAR(50) UNIQUE NOT NULL,
    device_id UUID REFERENCES devices(id),
    dealer_id UUID REFERENCES users(id),
    used_by_id UUID REFERENCES users(id),
    used_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    is_used BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_activation_keys_key_code ON activation_keys(key_code);
CREATE INDEX idx_activation_keys_device ON activation_keys(device_id);
CREATE INDEX idx_activation_keys_dealer ON activation_keys(dealer_id);
CREATE INDEX idx_activation_keys_expires_at ON activation_keys(expires_at);

COMMENT ON TABLE activation_keys IS 'Activation keys for device enrollment';
COMMENT ON COLUMN activation_keys.key_code IS 'Unique activation key for device enrollment';