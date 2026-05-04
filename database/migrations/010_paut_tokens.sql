-- Migration: 010_paut_tokens.sql
-- Description: PAUT (Push Authentication Token) management

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS paut_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) NOT NULL,
    token VARCHAR(500) NOT NULL,
    device_id UUID REFERENCES devices(id),
    device_name VARCHAR(255),
    expires_at TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT true,
    last_used_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_paut_tokens_user ON paut_tokens(user_id);
CREATE INDEX idx_paut_tokens_token ON paut_tokens(token);
CREATE INDEX idx_paut_tokens_expires_at ON paut_tokens(expires_at);
CREATE INDEX idx_paut_tokens_created_at ON paut_tokens(created_at);

COMMENT ON TABLE paut_tokens IS 'PAUT (Push Authentication Token) for device management';
COMMENT ON COLUMN paut_tokens.token IS 'Push Authentication Token for device commands';