-- Migration 123: allow transient command states on devices.status.
-- The backend uses these states while waiting for the managed phone to confirm.

ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_status_check;

ALTER TABLE devices ADD CONSTRAINT devices_status_check CHECK (
  status IN (
    'pending',
    'enrolled',
    'active',
    'locked',
    'unlocked',
    'partial_lock',
    'reminder',
    'pending_lock',
    'pending_unlock',
    'pending_decouple',
    'decoupled',
    'disabled',
    'suspended',
    'stolen'
  )
);
