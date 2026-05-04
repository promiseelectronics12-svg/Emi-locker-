-- Migration: 005_emi_payments.sql
-- Description: Individual EMI payment records

-- ENUM for payment method
CREATE TYPE payment_method AS ENUM (
    'upi',
    'bank_transfer',
    'cash',
    'card',
    'wallet',
    'other'
);

-- ENUM for payment status
CREATE TYPE payment_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed',
    'refunded',
    'disputed'
);

CREATE TABLE emi_payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emi_id          UUID NOT NULL REFERENCES emi_schedules(id) ON DELETE RESTRICT,
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    amount          NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    payment_date    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    method          payment_method NOT NULL,
    -- tx_id: external transaction reference from payment gateway
    tx_id           TEXT,
    status          payment_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_emi_payments_emi_id ON emi_payments (emi_id);
CREATE INDEX idx_emi_payments_device_id ON emi_payments (device_id);
CREATE INDEX idx_emi_payments_status ON emi_payments (status);
CREATE INDEX idx_emi_payments_payment_date ON emi_payments (payment_date);
CREATE INDEX idx_emi_payments_tx_id ON emi_payments (tx_id);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_emi_payments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_emi_payments_updated_at
    BEFORE UPDATE ON emi_payments
    FOR EACH ROW
    EXECUTE FUNCTION update_emi_payments_updated_at();
