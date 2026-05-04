-- Migration: 005_emi_payments.sql
-- Description: Payment records and transaction history

-- Replace with real domain before deploy

CREATE TABLE IF NOT EXISTS emi_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emi_schedule_id UUID REFERENCES emi_schedules(id),
    user_id UUID REFERENCES users(id),
    device_id UUID REFERENCES devices(id),
    amount DECIMAL(15, 2) NOT NULL,
    payment_month INTEGER NOT NULL,
    payment_year INTEGER NOT NULL,
    payment_date DATE,
    payment_method VARCHAR(50),
    transaction_ref VARCHAR(255),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed', 'overdue')),
    due_date DATE NOT NULL,
    paid_at TIMESTAMP,
    failure_reason VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_emi_payments_emi_schedule ON emi_payments(emi_schedule_id);
CREATE INDEX idx_emi_payments_user ON emi_payments(user_id);
CREATE INDEX idx_emi_payments_device ON emi_payments(device_id);
CREATE INDEX idx_emi_payments_status ON emi_payments(payment_status);
CREATE INDEX idx_emi_payments_due_date ON emi_payments(due_date);
CREATE INDEX idx_emi_payments_created_at ON emi_payments(created_at);

COMMENT ON TABLE emi_payments IS 'Payment records and transaction history';
COMMENT ON COLUMN emi_payments.payment_status IS 'pending, completed, failed, or overdue';
COMMENT ON COLUMN emi_payments.payment_method IS 'bKash, Nagad, Rocket, Bank Transfer, etc.';