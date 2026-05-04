-- Migration: 008_audit_log.sql
-- Description: Immutable audit log — NO UPDATE OR DELETE ALLOWED
-- Enforced via database triggers for tamper-proof compliance

CREATE TABLE audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id        UUID NOT NULL,
    -- actor_type: 'user', 'system', 'api', 'device'
    actor_type      TEXT NOT NULL CHECK (actor_type IN ('user', 'system', 'api', 'device')),
    device_id       UUID,
    action          TEXT NOT NULL,
    -- details_json: AES-256 encrypted at rest if contains PII
    details_json    JSONB,
    -- ip: source IP address of the actor
    ip              INET,
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IMMUTABILITY ENFORCEMENT: Prevent UPDATE on audit_log
CREATE OR REPLACE FUNCTION prevent_audit_log_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'UPDATE on audit_log is not allowed. Audit logs are immutable.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_log_no_update
    BEFORE UPDATE ON audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_update();

-- IMMUTABILITY ENFORCEMENT: Prevent DELETE on audit_log
CREATE OR REPLACE FUNCTION prevent_audit_log_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'DELETE on audit_log is not allowed. Audit logs are immutable.';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_log_no_delete
    BEFORE DELETE ON audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_delete();

-- Indexes for common query patterns
CREATE INDEX idx_audit_log_actor_id ON audit_log (actor_id);
CREATE INDEX idx_audit_log_actor_type ON audit_log (actor_type);
CREATE INDEX idx_audit_log_device_id ON audit_log (device_id);
CREATE INDEX idx_audit_log_action ON audit_log (action);
CREATE INDEX idx_audit_log_timestamp ON audit_log (timestamp);

-- Composite index for device history queries
CREATE INDEX idx_audit_log_device_timestamp ON audit_log (device_id, timestamp DESC);
