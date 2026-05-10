-- Store EMI terms with a pending enrollment. The real active schedule is
-- created only after the device confirms the binding code.
ALTER TABLE enrollments
  ADD COLUMN IF NOT EXISTS total_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS down_payment NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS emi_amount NUMERIC,
  ADD COLUMN IF NOT EXISTS duration INTEGER,
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS grace_days INTEGER DEFAULT 7;

CREATE INDEX IF NOT EXISTS idx_enrollments_device_status
  ON enrollments(device_id, status);

CREATE INDEX IF NOT EXISTS idx_emi_schedules_device_status
  ON emi_schedules(device_id, status);
