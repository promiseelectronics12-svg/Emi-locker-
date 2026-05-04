-- Migration: 011_commands.sql
-- Description: Command signing table for device lock/unlock/decouple commands
-- Every command signed with device IMEI + timestamp + nonce to prevent replay and forgery

-- ENUM for command types
CREATE TYPE command_type AS ENUM (
    'lock',
    'unlock',
    'decouple',
    'config_change'
);

CREATE TABLE commands (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    command_type    command_type NOT NULL,
    payload_json    JSONB,
    imei_hash       TEXT,
    nonce           TEXT NOT NULL UNIQUE,
    timestamp       TIMESTAMPTZ NOT NULL,
    hmac_signature  TEXT NOT NULL,
    executed        BOOLEAN NOT NULL DEFAULT FALSE,
    executed_at     TIMESTAMPTZ,
    created_by      UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_commands_device_id ON commands (device_id);
CREATE INDEX idx_commands_command_type ON commands (command_type);
CREATE INDEX idx_commands_nonce ON commands (nonce);
CREATE INDEX idx_commands_executed ON commands (executed);
CREATE INDEX idx_commands_created_at ON commands (created_at);
CREATE INDEX idx_commands_created_by ON commands (created_by);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_commands_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_commands_updated_at
    BEFORE UPDATE ON commands
    FOR EACH ROW
    EXECUTE FUNCTION update_commands_updated_at();