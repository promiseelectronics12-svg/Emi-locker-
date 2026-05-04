-- Migration: 006_lock_requests.sql
-- Description: Device lock/unlock request queue

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS lock_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id),
    requested_by UUID REFERENCES users(id),
    request_type VARCHAR(20) NOT NULL CHECK (request_type IN ('lock', 'unlock')),
    reason VARCHAR(500),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    admin_notes VARCHAR(1000),
    processed_by UUID REFERENCES users(id),
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_lock_requests_device ON lock_requests(device_id);
CREATE INDEX idx_lock_requests_requested_by ON lock_requests(requested_by);
CREATE INDEX idx_lock_requests_status ON lock_requests(status);
CREATE INDEX idx_lock_requests_request_type ON lock_requests(request_type);
CREATE INDEX idx_lock_requests_created_at ON lock_requests(created_at);

COMMENT ON TABLE lock_requests IS 'Device lock/unlock request queue';
COMMENT ON COLUMN lock_requests.request_type IS 'lock or unlock request';