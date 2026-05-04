-- Migration: 016_geofences.sql
-- Description: Geofencing management and alerts

CREATE TABLE geofences (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    type            TEXT NOT NULL CHECK (type IN ('circle', 'polygon')),
    center_latitude DECIMAL(10, 8),
    center_longitude DECIMAL(11, 8),
    radius_meters   INTEGER,
    coordinates     JSONB, -- For polygons
    enabled         BOOLEAN DEFAULT true,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geofences_device_id ON geofences(device_id);
CREATE INDEX idx_geofences_enabled ON geofences(enabled);

CREATE TABLE geofence_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    geofence_id     UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
    alert_id        TEXT UNIQUE NOT NULL,
    latitude        DECIMAL(10, 8) NOT NULL,
    longitude       DECIMAL(11, 8) NOT NULL,
    triggered_at    TIMESTAMPTZ DEFAULT NOW(),
    acknowledged    BOOLEAN DEFAULT false,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_geofence_alerts_device_id ON geofence_alerts(device_id);
CREATE INDEX idx_geofence_alerts_alert_id ON geofence_alerts(alert_id);
CREATE INDEX idx_geofence_alerts_acknowledged ON geofence_alerts(acknowledged);
