-- Migration: 007_decoupling.sql
-- Description: Device decoupling/separation state machine
-- Handles the process when a device is separated from EMI obligations

-- ENUM for decoupling state
CREATE TYPE decoupling_state AS ENUM (
    'initiated',
    'dealer_notified',
    'pending_fraud_check',
    'fraud_hold',
    'admin_review',
    'approved',
    'rejected',
    'completed',
    'cancelled'
);

CREATE TABLE decoupling (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id           UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    emi_id              UUID NOT NULL REFERENCES emi_schedules(id) ON DELETE RESTRICT,
    initiated_by        UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    state               decoupling_state NOT NULL DEFAULT 'initiated',
    dealer_notified_at  TIMESTAMPTZ,
    -- fraud_flag: AES-256 encrypted at rest if contains sensitive details
    fraud_flag          BOOLEAN NOT NULL DEFAULT FALSE,
    admin_reviewed_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    admin_action_at     TIMESTAMPTZ,
    -- rtoc_code: Real-Time Operations Center reference code
    rtoc_code           TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_decoupling_device_id ON decoupling (device_id);
CREATE INDEX idx_decoupling_emi_id ON decoupling (emi_id);
CREATE INDEX idx_decoupling_initiated_by ON decoupling (initiated_by);
CREATE INDEX idx_decoupling_admin_reviewed_by ON decoupling (admin_reviewed_by);
CREATE INDEX idx_decoupling_state ON decoupling (state);
CREATE INDEX idx_decoupling_fraud_flag ON decoupling (fraud_flag);
CREATE INDEX idx_decoupling_created_at ON decoupling (created_at);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_decoupling_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_decoupling_updated_at
    BEFORE UPDATE ON decoupling
    FOR EACH ROW
    EXECUTE FUNCTION update_decoupling_updated_at();
