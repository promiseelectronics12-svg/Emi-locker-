-- Migration: 017_alerts.sql
-- Description: General system and device alerts

CREATE TABLE alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dealer_id       UUID REFERENCES users(id), -- Or specific dealer link
    device_id       UUID REFERENCES devices(id) ON DELETE CASCADE,
    alert_type      TEXT NOT NULL,
    title           TEXT NOT NULL,
    message         TEXT,
    metadata        JSONB,
    status          TEXT DEFAULT 'active',
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_alerts_dealer_id ON alerts(dealer_id);
CREATE INDEX idx_alerts_device_id ON alerts(device_id);
CREATE INDEX idx_alerts_status ON alerts(status);
CREATE INDEX idx_alerts_created_at ON alerts(created_at DESC);
