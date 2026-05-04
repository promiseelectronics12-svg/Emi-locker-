-- Migration: 006_lock_requests.sql
-- Description: Device lock/unlock requests with server-side verdict

-- ENUM for lock reason codes
CREATE TYPE lock_reason_code AS ENUM (
    'emi_default',
    'fraud_detected',
    'stolen_report',
    'manual_lock',
    'policy_violation',
    'court_order',
    'other'
);

-- ENUM for lock request status
CREATE TYPE lock_request_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'executed',
    'cancelled',
    'expired'
);

-- ENUM for server verdict
CREATE TYPE server_verdict AS ENUM (
    'allow_lock',
    'deny_lock',
    'allow_unlock',
    'deny_unlock',
    'requires_review'
);

CREATE TABLE lock_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    dealer_id       UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    requested_by    UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reason_code     lock_reason_code NOT NULL,
    note            TEXT,
    status          lock_request_status NOT NULL DEFAULT 'pending',
    server_verdict  server_verdict,
    verdict_reason  TEXT,
    executed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lock_requests_device_id ON lock_requests (device_id);
CREATE INDEX idx_lock_requests_dealer_id ON lock_requests (dealer_id);
CREATE INDEX idx_lock_requests_requested_by ON lock_requests (requested_by);
CREATE INDEX idx_lock_requests_status ON lock_requests (status);
CREATE INDEX idx_lock_requests_server_verdict ON lock_requests (server_verdict);
CREATE INDEX idx_lock_requests_created_at ON lock_requests (created_at);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_lock_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_lock_requests_updated_at
    BEFORE UPDATE ON lock_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_lock_requests_updated_at();
