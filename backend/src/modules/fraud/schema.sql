-- Security Events Table
CREATE TABLE IF NOT EXISTS security_events (
    id UUID PRIMARY KEY,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    event_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    details JSONB NOT NULL DEFAULT '{}',
    created_by VARCHAR(255),
    resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by VARCHAR(255),
    resolved_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_events_device_id ON security_events(device_id);
CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON security_events(severity);
CREATE INDEX IF NOT EXISTS idx_security_events_resolved ON security_events(resolved);
CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at);

-- NEIR Report Queue Table
CREATE TABLE IF NOT EXISTS neir_report_queue (
    id UUID PRIMARY KEY,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    imei VARCHAR(20),
    nid VARCHAR(30),
    dealer_id UUID,
    reason TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    submitted_by VARCHAR(255),
    submitted_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_neir_queue_device_id ON neir_report_queue(device_id);
CREATE INDEX IF NOT EXISTS idx_neir_queue_status ON neir_report_queue(status);
CREATE INDEX IF NOT EXISTS idx_neir_queue_created_at ON neir_report_queue(created_at);

-- Add constraint for valid NEIR queue statuses
ALTER TABLE neir_report_queue DROP CONSTRAINT IF EXISTS chk_neir_status;
ALTER TABLE neir_report_queue ADD CONSTRAINT chk_neir_status
    CHECK (status IN ('pending', 'flagged', 'submitted', 'rejected'));

-- Add constraint for valid security event types
ALTER TABLE security_events DROP CONSTRAINT IF EXISTS chk_event_type;
ALTER TABLE security_events ADD CONSTRAINT chk_event_type
    CHECK (event_type IN (
        'INTEGRITY_FAILURE',
        'LOCATION_ANOMALY',
        'IMEI_MULTIREGISTER',
        'DEVICE_OFFLINE_OVERDUE',
        'DEALER_FRAUD_RATE',
        'MANUAL_FLAG'
    ));

-- Add constraint for valid severity levels
ALTER TABLE security_events DROP CONSTRAINT IF EXISTS chk_severity;
ALTER TABLE security_events ADD CONSTRAINT chk_severity
    CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'));