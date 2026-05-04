-- Migration: 008_audit_log.sql
-- Description: Comprehensive audit logging

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_log_user ON audit_log(user_id);
CREATE INDEX idx_audit_log_action ON audit_log(action);
CREATE INDEX idx_audit_log_entity_type ON audit_log(entity_type);
CREATE INDEX idx_audit_log_entity_id ON audit_log(entity_id);
CREATE INDEX idx_audit_log_created_at ON audit_log(created_at);

COMMENT ON TABLE audit_log IS 'Comprehensive audit logging for all sensitive operations';
COMMENT ON COLUMN audit_log.action IS 'Action performed (e.g., USER_LOGIN, DEVICE_LOCK, PAYMENT_CREATE)';
COMMENT ON COLUMN audit_log.entity_type IS 'Type of entity affected (e.g., users, devices, emi_payments)';