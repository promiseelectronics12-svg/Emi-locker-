-- Migration: 004_emi_schedules.sql
-- Description: EMI payment schedules and terms

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS emi_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id),
    user_id UUID REFERENCES users(id),
    total_amount DECIMAL(15, 2) NOT NULL,
    down_payment DECIMAL(15, 2) DEFAULT 0,
    monthly_payment DECIMAL(15, 2) NOT NULL,
    tenure_months INTEGER NOT NULL,
    interest_rate DECIMAL(5, 2) DEFAULT 0,
    emi_start_date DATE NOT NULL,
    emi_end_date DATE NOT NULL,
    grace_period_days INTEGER DEFAULT 3,
    penalty_per_day DECIMAL(10, 2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'completed', 'defaulted', 'cancelled')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_emi_schedules_device ON emi_schedules(device_id);
CREATE INDEX idx_emi_schedules_user ON emi_schedules(user_id);
CREATE INDEX idx_emi_schedules_status ON emi_schedules(status);
CREATE INDEX idx_emi_schedules_created_at ON emi_schedules(created_at);

COMMENT ON TABLE emi_schedules IS 'EMI payment schedules with configurable terms';
COMMENT ON COLUMN emi_schedules.grace_period_days IS 'Days allowed after due date before penalty';
COMMENT ON COLUMN emi_schedules.penalty_per_day IS 'Penalty amount per day of default';