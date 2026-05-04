-- Migration: 004_emi_schedules.sql
-- Description: EMI (Equated Monthly Installment) payment schedules

-- ENUM for EMI schedule status
CREATE TYPE emi_schedule_status AS ENUM (
    'pending',
    'active',
    'completed',
    'defaulted',
    'restructured',
    'cancelled'
);

CREATE TABLE emi_schedules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    total_amount    NUMERIC(12, 2) NOT NULL CHECK (total_amount > 0),
    emi_amount      NUMERIC(12, 2) NOT NULL CHECK (emi_amount > 0),
    duration_months INTEGER NOT NULL CHECK (duration_months > 0),
    start_date      DATE NOT NULL,
    grace_days      INTEGER NOT NULL DEFAULT 5 CHECK (grace_days >= 0),
    status          emi_schedule_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_emi_schedules_device_id ON emi_schedules (device_id);
CREATE INDEX idx_emi_schedules_status ON emi_schedules (status);
CREATE INDEX idx_emi_schedules_start_date ON emi_schedules (start_date);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_emi_schedules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_emi_schedules_updated_at
    BEFORE UPDATE ON emi_schedules
    FOR EACH ROW
    EXECUTE FUNCTION update_emi_schedules_updated_at();
