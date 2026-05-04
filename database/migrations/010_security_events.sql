-- Migration: 009_security_events.sql
-- Description: Security event tracking and incident management

-- ENUM for security event types
CREATE TYPE security_event_type AS ENUM (
    'unauthorized_unlock_attempt',
    'adb_enabled',
    'usb_debugging_enabled',
    'unknown_source_install',
    'root_detected',
    'tamper_detected',
    'location_spoofing',
    'sim_swap',
    'factory_reset_attempt',
    'frp_bypass_attempt',
    'policy_violation',
    'suspicious_api_call',
    'key_exfiltration_attempt',
    'other'
);

-- ENUM for severity levels
CREATE TYPE security_severity AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TABLE security_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    event_type      security_event_type NOT NULL,
    severity        security_severity NOT NULL DEFAULT 'medium',
    -- details_json: AES-256 encrypted at rest if contains sensitive data
    details_json    JSONB,
    resolved        BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at     TIMESTAMPTZ,
    resolved_by     UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_security_events_device_id ON security_events (device_id);
CREATE INDEX idx_security_events_event_type ON security_events (event_type);
CREATE INDEX idx_security_events_severity ON security_events (severity);
CREATE INDEX idx_security_events_resolved ON security_events (resolved);
CREATE INDEX idx_security_events_created_at ON security_events (created_at);

-- Composite index for unresolved high-severity alerts
CREATE INDEX idx_security_events_unresolved_critical
    ON security_events (severity, resolved, created_at DESC)
    WHERE resolved = FALSE AND severity IN ('high', 'critical');
