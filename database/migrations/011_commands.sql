-- Migration: 011_commands.sql
-- Description: Remote device command queue

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS commands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id) NOT NULL,
    command_type VARCHAR(50) NOT NULL,
    payload JSONB,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'executed', 'failed')),
    priority INTEGER DEFAULT 0,
    sent_at TIMESTAMP,
    delivered_at TIMESTAMP,
    executed_at TIMESTAMP,
    failure_reason VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_commands_device ON commands(device_id);
CREATE INDEX idx_commands_command_type ON commands(command_type);
CREATE INDEX idx_commands_status ON commands(status);
CREATE INDEX idx_commands_priority ON commands(priority);
CREATE INDEX idx_commands_created_at ON commands(created_at);

COMMENT ON TABLE commands IS 'Remote device command queue for lock/unlock and other commands';
COMMENT ON COLUMN commands.command_type IS 'e.g., LOCK_DEVICE, UNLOCK_DEVICE, WIPE_DATA, LOCATE';
COMMENT ON COLUMN commands.payload IS 'Command-specific payload data';