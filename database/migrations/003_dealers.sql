-- Migration: 003_dealers.sql
-- Description: Dealer profiles linked to users table

CREATE TABLE dealers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    email           TEXT NOT NULL, -- Plaintext for display/search if allowed, or sync with users
    phone           TEXT,
    address         TEXT,
    nid             TEXT,
    business_name   TEXT,
    role            TEXT DEFAULT 'dealer',
    shop_latitude   DECIMAL(10, 8),
    shop_longitude  DECIMAL(11, 8),
    status          TEXT DEFAULT 'active',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT dealers_user_id_unique UNIQUE (user_id)
);

CREATE INDEX idx_dealers_user_id ON dealers(user_id);
CREATE INDEX idx_dealers_role ON dealers(role);
CREATE INDEX idx_dealers_status ON dealers(status);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_dealers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_dealers_updated_at
    BEFORE UPDATE ON dealers
    FOR EACH ROW
    EXECUTE FUNCTION update_dealers_updated_at();
