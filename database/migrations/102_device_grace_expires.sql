-- Migration 102: Device grace unlock columns + dealer phone
-- grace_expires_at: when set, device is in a temporary grace unlock period.
--   The lock scheduler checks this every 5 minutes and re-locks expired devices.
--   Cleared automatically on re-lock, or when EMI is fully paid.
-- dealer_phone: copied from dealer record at enrollment. Pushed to customer device
--   app so the locked screen always shows who to call. Also used by the customer app
--   to verify that an incoming SMS OTP came from the authentic dealer number.
-- last_fake_shutdown_at: set when device reports a fake-shutdown theft-protection event.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS grace_expires_at        TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS dealer_phone             TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS last_fake_shutdown_at    TIMESTAMPTZ;

COMMENT ON COLUMN devices.grace_expires_at IS
  'Temporary grace unlock expiry. NULL = not in grace period. '
  'Auto-relocked by scheduler when this timestamp passes.';

COMMENT ON COLUMN devices.dealer_phone IS
  'Dealer registered phone number at enrollment time. '
  'Shown on customer locked screen and used to verify SMS OTP authenticity.';

COMMENT ON COLUMN devices.last_fake_shutdown_at IS
  'Timestamp of the most recent fake-shutdown theft-protection trigger. '
  'Set when device intercepts a shutdown intent and keeps running silently.';

-- Partial index — only devices currently in grace period are indexed.
-- Keeps the scheduler query fast even with millions of device rows.
CREATE INDEX IF NOT EXISTS idx_devices_grace_expires
  ON devices(grace_expires_at)
  WHERE grace_expires_at IS NOT NULL;
