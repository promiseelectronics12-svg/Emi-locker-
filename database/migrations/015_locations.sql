-- Migration: 015_locations.sql
-- Description: Device location reporting and pull requests

CREATE TABLE location_reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    latitude        DECIMAL(10, 8) NOT NULL,
    longitude       DECIMAL(11, 8) NOT NULL,
    accuracy        DECIMAL(10, 2) NOT NULL,
    timestamp       TIMESTAMPTZ NOT NULL,
    battery_level   INTEGER,
    pull_id         TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_location_reports_device_id ON location_reports(device_id);
CREATE INDEX idx_location_reports_timestamp ON location_reports(timestamp DESC);

CREATE TABLE location_pull_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    pull_id         TEXT UNIQUE NOT NULL,
    reason          TEXT NOT NULL,
    requested_by    UUID REFERENCES users(id),
    status          TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'responded', 'expired', 'failed')),
    requested_at    TIMESTAMPTZ DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_location_pull_requests_device_id ON location_pull_requests(device_id);
CREATE INDEX idx_location_pull_requests_status ON location_pull_requests(status);
CREATE INDEX idx_location_pull_requests_pull_id ON location_pull_requests(pull_id);
