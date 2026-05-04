-- Migration: 009_security_events.sql
-- Description: Security event tracking

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    device_id UUID REFERENCES devices(id),
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    description VARCHAR(500),
    ip_address VARCHAR(45),
    location VARCHAR(255),
    is_resolved BOOLEAN DEFAULT false,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP,
    resolution_notes VARCHAR(1000),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_security_events_user ON security_events(user_id);
CREATE INDEX idx_security_events_device ON security_events(device_id);
CREATE INDEX idx_security_events_event_type ON security_events(event_type);
CREATE INDEX idx_security_events_severity ON security_events(severity);
CREATE INDEX idx_security_events_is_resolved ON security_events(is_resolved);
CREATE INDEX idx_security_events_created_at ON security_events(created_at);

COMMENT ON TABLE security_events IS 'Security event tracking for failed logins, policy violations, etc.';
COMMENT ON COLUMN security_events.event_type IS 'e.g., FAILED_LOGIN, POLICY_VIOLATION, SUSPICIOUS_ACTIVITY';
COMMENT ON COLUMN security_events.severity IS 'low, medium, high, or critical';