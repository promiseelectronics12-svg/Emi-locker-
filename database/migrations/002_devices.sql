-- Migration: 002_devices.sql
-- Description: Devices table for Android device management via AMAPI
-- Sensitive fields (imei, serial) encrypted at rest with AES-256

-- ENUM for device state machine
CREATE TYPE device_state AS ENUM (
    'enrolled',
    'active',
    'locked',
    'unlocked',
    'suspended',
    'decommissioned',
    'lost',
    'stolen'
);

CREATE TABLE devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- imei: AES-256 encrypted at rest, stored as BYTEA
    imei            BYTEA NOT NULL,
    -- serial: AES-256 encrypted at rest, stored as BYTEA
    serial          BYTEA NOT NULL,
    soc_model       TEXT NOT NULL,
    customer_id     UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    dealer_id       UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    state           device_state NOT NULL DEFAULT 'enrolled',
    -- amapi_device_id: Android Management API device resource name
    amapi_device_id TEXT,
    -- fcm_token: Firebase Cloud Messaging push token, AES-256 encrypted at rest
    fcm_token       BYTEA,
    enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_devices_customer_id ON devices (customer_id);
CREATE INDEX idx_devices_dealer_id ON devices (dealer_id);
CREATE INDEX idx_devices_state ON devices (state);
CREATE INDEX idx_devices_amapi_device_id ON devices (amapi_device_id);
CREATE INDEX idx_devices_enrolled_at ON devices (enrolled_at);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_devices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_devices_updated_at
    BEFORE UPDATE ON devices
    FOR EACH ROW
    EXECUTE FUNCTION update_devices_updated_at();
