-- Migration 132: Customer EMI Locker app FCM token
-- Keeps visible customer-app notifications separate from DeviceProtectionService
-- lock-command delivery, which continues to use devices.fcm_token.

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS emi_locker_fcm_token TEXT,
  ADD COLUMN IF NOT EXISTS emi_locker_fcm_token_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN devices.emi_locker_fcm_token IS
  'FCM token for the visible EMI Locker customer app. Do not use for lock/unlock commands.';

COMMENT ON COLUMN devices.emi_locker_fcm_token_updated_at IS
  'Last time the visible EMI Locker customer app FCM token was registered.';
