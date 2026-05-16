-- Migration 125: allow QR/code-first enrollment without manual IMEI or EMI terms.
-- No new tables. This relaxes existing columns so device details can be filled
-- by the user app after Device Owner setup, with dealer manual entry as fallback.

ALTER TABLE enrollments ALTER COLUMN imei1 DROP NOT NULL;
ALTER TABLE devices ALTER COLUMN imei DROP NOT NULL;
