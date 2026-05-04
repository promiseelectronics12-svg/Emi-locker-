-- Location Reports Table
CREATE TABLE IF NOT EXISTS location_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    accuracy DECIMAL(10, 2) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    battery_level INTEGER,
    pull_id VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_location_reports_device_id ON location_reports(device_id);
CREATE INDEX IF NOT EXISTS idx_location_reports_timestamp ON location_reports(timestamp DESC);

-- Location Pull Requests Table
CREATE TABLE IF NOT EXISTS location_pull_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    pull_id VARCHAR(255) UNIQUE NOT NULL,
    reason VARCHAR(255) NOT NULL,
    requested_by UUID REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending',
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_location_pull_requests_device_id ON location_pull_requests(device_id);
CREATE INDEX IF NOT EXISTS idx_location_pull_requests_status ON location_pull_requests(status);
CREATE INDEX IF NOT EXISTS idx_location_pull_requests_pull_id ON location_pull_requests(pull_id);

-- Geofences Table
CREATE TABLE IF NOT EXISTS geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('circle', 'polygon')),
    center_latitude DECIMAL(10, 8),
    center_longitude DECIMAL(11, 8),
    radius_meters INTEGER,
    coordinates JSONB,
    enabled BOOLEAN DEFAULT true,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geofences_device_id ON geofences(device_id);
CREATE INDEX IF NOT EXISTS idx_geofences_enabled ON geofences(enabled);

-- Geofence Alerts Table
CREATE TABLE IF NOT EXISTS geofence_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    geofence_id UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    alert_id VARCHAR(255) UNIQUE NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    acknowledged BOOLEAN DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geofence_alerts_device_id ON geofence_alerts(device_id);
CREATE INDEX IF NOT EXISTS idx_geofence_alerts_alert_id ON geofence_alerts(alert_id);
CREATE INDEX IF NOT EXISTS idx_geofence_alerts_acknowledged ON geofence_alerts(acknowledged);

-- Alerts Table (for dealer notifications)
CREATE TABLE IF NOT EXISTS alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id UUID REFERENCES users(id),
    device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
    alert_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT,
    metadata JSONB,
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_dealer_id ON alerts(dealer_id);
CREATE INDEX IF NOT EXISTS idx_alerts_device_id ON alerts(device_id);
CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status);
CREATE INDEX IF NOT EXISTS idx_alerts_created_at ON alerts(created_at DESC);