-- Migration: 007_decoupling.sql
-- Description: Device decoupled status after full payment

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS decoupled_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id) UNIQUE NOT NULL,
    owner_id UUID REFERENCES users(id),
    decoupling_date DATE NOT NULL,
    final_payment_id UUID REFERENCES emi_payments(id),
    device_name VARCHAR(255),
    imei VARCHAR(20),
    is_decoupled BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_decoupled_devices_device ON decoupled_devices(device_id);
CREATE INDEX idx_decoupled_devices_owner ON decoupled_devices(owner_id);
CREATE INDEX idx_decoupled_devices_created_at ON decoupled_devices(created_at);

COMMENT ON TABLE decoupled_devices IS 'Devices decoupled after full EMI payment';