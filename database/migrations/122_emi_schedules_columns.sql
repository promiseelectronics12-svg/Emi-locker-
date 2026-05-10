-- Migration: 122_emi_schedules_columns.sql
-- Add down_payment and alias duration_months → duration in emi_schedules.
-- The enrollment service inserts using 'duration' and 'down_payment'.
-- Without these columns confirmFromDevice fails at the emi_schedules INSERT.

ALTER TABLE emi_schedules
  ADD COLUMN IF NOT EXISTS down_payment NUMERIC(12, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS duration     INTEGER;

-- Back-fill duration from duration_months for existing rows
UPDATE emi_schedules
SET duration = duration_months
WHERE duration IS NULL AND duration_months IS NOT NULL;

-- Make duration NOT NULL now that it is filled
ALTER TABLE emi_schedules
  ALTER COLUMN duration SET NOT NULL;
