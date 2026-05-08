-- Migration: 099_unify_schema.sql
-- Purpose: Final compatibility gate for legacy/prototype schema variants.
-- Canonical contracts after this migration:
--   activation_keys, devices.status, emi_payments.emi_schedule_id

BEGIN;

-- ---------------------------------------------------------------------------
-- Users/dealers/resellers compatibility columns used by active services.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'email' AND data_type = 'bytea'
  ) THEN
    ALTER TABLE users ALTER COLUMN email TYPE TEXT USING encode(email, 'escape');
  ELSE
    ALTER TABLE users ALTER COLUMN email TYPE TEXT USING email::TEXT;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'phone' AND data_type = 'bytea'
  ) THEN
    ALTER TABLE users ALTER COLUMN phone TYPE TEXT USING encode(phone, 'escape');
  ELSE
    ALTER TABLE users ALTER COLUMN phone TYPE TEXT USING phone::TEXT;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'totp_secret' AND data_type = 'bytea'
  ) THEN
    ALTER TABLE users ALTER COLUMN totp_secret TYPE TEXT USING encode(totp_secret, 'escape');
  ELSE
    ALTER TABLE users ALTER COLUMN totp_secret TYPE TEXT USING totp_secret::TEXT;
  END IF;

  ALTER TABLE users ALTER COLUMN status TYPE TEXT USING status::TEXT;
  ALTER TABLE users ALTER COLUMN role TYPE TEXT USING role::TEXT;
END $$;

ALTER TABLE users ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_text TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS nid TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS totp_pending BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS backup_codes JSONB;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_by UUID;

DO $$
DECLARE
  archive_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'audit_logs'
      AND column_name = 'user_id'
      AND data_type <> 'uuid'
  ) THEN
    archive_name := '_legacy_audit_logs_' || to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
    EXECUTE format('ALTER TABLE audit_logs RENAME TO %I', archive_name);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  action TEXT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS resellers (
  id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  name TEXT,
  email TEXT,
  phone TEXT,
  company_name TEXT,
  trade_license TEXT,
  address TEXT,
  status TEXT DEFAULT 'pending',
  monthly_key_quota INTEGER DEFAULT 100,
  monthly_quota INTEGER DEFAULT 100,
  used_keys INTEGER DEFAULT 0,
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES users(id),
  suspended_at TIMESTAMPTZ,
  suspended_by UUID REFERENCES users(id),
  suspension_reason TEXT,
  quota_updated_at TIMESTAMPTZ,
  quota_updated_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE resellers ADD COLUMN IF NOT EXISTS monthly_key_quota INTEGER DEFAULT 100;
ALTER TABLE resellers ADD COLUMN IF NOT EXISTS monthly_quota INTEGER DEFAULT 100;
ALTER TABLE resellers ADD COLUMN IF NOT EXISTS used_keys INTEGER DEFAULT 0;
UPDATE resellers SET monthly_key_quota = COALESCE(monthly_key_quota, monthly_quota, 100);
UPDATE resellers SET monthly_quota = COALESCE(monthly_quota, monthly_key_quota, 100);

ALTER TABLE dealers ADD COLUMN IF NOT EXISTS reseller_id UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS business_name TEXT;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS shop_name TEXT;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS trade_license TEXT;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;
ALTER TABLE dealers ADD COLUMN IF NOT EXISTS reactivated_at TIMESTAMPTZ;
UPDATE dealers SET business_name = COALESCE(business_name, shop_name);
UPDATE dealers d
SET user_id = u.id
FROM users u
WHERE d.user_id IS NULL
  AND LOWER(d.email) = LOWER(u.email)
  AND u.role = 'dealer';
CREATE UNIQUE INDEX IF NOT EXISTS idx_dealers_user_id ON dealers(user_id) WHERE user_id IS NOT NULL;

DO $$
DECLARE
  archive_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'key_requests'
      AND column_name = 'id'
      AND data_type <> 'uuid'
  ) THEN
    archive_name := '_legacy_key_requests_' || to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
    EXECUTE format('ALTER TABLE key_requests RENAME TO %I', archive_name);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS key_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reseller_id UUID NOT NULL REFERENCES resellers(id),
  quantity INTEGER NOT NULL,
  justification TEXT,
  status TEXT DEFAULT 'pending',
  approved_quantity INTEGER,
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  rejected_by UUID REFERENCES users(id),
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS approved_quantity INTEGER;
ALTER TABLE key_requests ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE key_requests ALTER COLUMN status TYPE TEXT USING LOWER(status::TEXT);
UPDATE key_requests SET status = 'pending' WHERE status IN ('pending_admin', 'pending');
UPDATE key_requests SET status = 'approved' WHERE status = 'approved';
UPDATE key_requests SET status = 'rejected' WHERE status = 'rejected';
UPDATE key_requests SET status = 'pending' WHERE status IS NULL OR status NOT IN ('pending', 'approved', 'rejected');

-- ---------------------------------------------------------------------------
-- Devices: status is canonical. state is migration-only.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS activation_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

DO $$
DECLARE
  chk_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'state'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'status'
  ) THEN
    ALTER TABLE devices ALTER COLUMN state TYPE TEXT USING state::TEXT;
    ALTER TABLE devices RENAME COLUMN state TO status;
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'state'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'status'
  ) THEN
    ALTER TABLE devices ALTER COLUMN status TYPE TEXT USING status::TEXT;
    UPDATE devices SET status = COALESCE(status, state::TEXT);
    ALTER TABLE devices DROP COLUMN state;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'status'
  ) THEN
    ALTER TABLE devices ALTER COLUMN status TYPE TEXT USING status::TEXT;
  END IF;

  FOR chk_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'devices'::regclass
      AND con.contype = 'c'
      AND att.attname IN ('status', 'lock_level')
  LOOP
    EXECUTE format('ALTER TABLE devices DROP CONSTRAINT %I', chk_name);
  END LOOP;
END $$;

ALTER TABLE devices ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'enrolled';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS serial_number TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS soc_id TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_name TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS amapi_device_name TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS amapi_device_id TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS managed_google_account TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS enrollment_token TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS enrolled_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE devices ADD COLUMN IF NOT EXISTS policy_last_applied TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_hash TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_salt TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_reason TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS decoupling_initiated_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS decoupling_window_expires_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fraud_flagged BOOLEAN DEFAULT FALSE;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS imei_hash TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS reseller_id UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS activation_key_id UUID REFERENCES activation_keys(id) ON DELETE SET NULL;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS totp_secret TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level TEXT DEFAULT 'NONE';
ALTER TABLE devices ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

DO $$
DECLARE
  fk_name TEXT;
BEGIN
  FOR fk_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'devices'::regclass
      AND con.contype = 'f'
      AND att.attname = 'dealer_id'
  LOOP
    EXECUTE format('ALTER TABLE devices DROP CONSTRAINT %I', fk_name);
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'imei' AND data_type = 'bytea'
  ) THEN
    ALTER TABLE devices ALTER COLUMN imei TYPE TEXT USING encode(imei, 'hex');
  ELSE
    ALTER TABLE devices ALTER COLUMN imei TYPE TEXT USING imei::TEXT;
  END IF;
END $$;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'fcm_token' AND data_type = 'bytea'
  ) THEN
    ALTER TABLE devices ALTER COLUMN fcm_token TYPE TEXT USING encode(fcm_token, 'escape');
  ELSE
    ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token TEXT;
    ALTER TABLE devices ALTER COLUMN fcm_token TYPE TEXT USING fcm_token::TEXT;
  END IF;
END $$;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'serial'
  ) THEN
    ALTER TABLE devices ALTER COLUMN serial DROP NOT NULL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'customer_id'
  ) THEN
    ALTER TABLE devices ALTER COLUMN customer_id DROP NOT NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'serial'
  ) THEN
    UPDATE devices SET serial_number = COALESCE(serial_number, encode(serial, 'hex'))
    WHERE serial_number IS NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'soc_model'
  ) THEN
    UPDATE devices SET soc_id = COALESCE(soc_id, soc_model)
    WHERE soc_id IS NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'customer_id'
  ) THEN
    UPDATE devices SET owner_id = COALESCE(owner_id, customer_id)
    WHERE owner_id IS NULL;
  END IF;
END $$;

DO $$
DECLARE
  chk_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'devices' AND column_name = 'lock_level'
  ) THEN
    ALTER TABLE devices ALTER COLUMN lock_level DROP DEFAULT;
    ALTER TABLE devices ALTER COLUMN lock_level TYPE TEXT USING
      CASE UPPER(COALESCE(lock_level::TEXT, 'NONE'))
        WHEN '0' THEN 'NONE'
        WHEN '1' THEN 'SOFT'
        WHEN '2' THEN 'FULL'
        WHEN '3' THEN 'WIPE'
        WHEN 'UNLOCKED' THEN 'NONE'
        WHEN 'SOFT_LOCK' THEN 'SOFT'
        WHEN 'FULL_LOCK' THEN 'FULL'
        WHEN 'HARD' THEN 'FULL'
        WHEN 'HARD_LOCK' THEN 'FULL'
        ELSE UPPER(COALESCE(lock_level::TEXT, 'NONE'))
      END;
  END IF;

  FOR chk_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'devices'::regclass
      AND con.contype = 'c'
      AND att.attname = 'lock_level'
  LOOP
    EXECUTE format('ALTER TABLE devices DROP CONSTRAINT %I', chk_name);
  END LOOP;
END $$;

UPDATE devices SET lock_level = 'NONE' WHERE lock_level IS NULL;
ALTER TABLE devices ALTER COLUMN lock_level SET DEFAULT 'NONE';
ALTER TABLE devices ALTER COLUMN lock_level SET NOT NULL;
ALTER TABLE devices ADD CONSTRAINT devices_lock_level_check
  CHECK (lock_level IN ('NONE', 'SOFT', 'FULL', 'WIPE'));

CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_owner_id ON devices(owner_id);
CREATE INDEX IF NOT EXISTS idx_devices_reseller_id ON devices(reseller_id);
CREATE INDEX IF NOT EXISTS idx_devices_activation_key_id ON devices(activation_key_id);

-- ---------------------------------------------------------------------------
-- Activation keys: canonical table/columns/statuses, no expiry contract.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  archive_name TEXT;
  chk_name TEXT;
  fk_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'keys'
  ) THEN
    archive_name := '_legacy_keys_' || to_char(clock_timestamp(), 'YYYYMMDD_HH24MISS_US');
    EXECUTE format('ALTER TABLE keys RENAME TO %I', archive_name);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'key_code'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'key_string'
  ) THEN
    ALTER TABLE activation_keys RENAME COLUMN key_code TO key_string;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'key_hash'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'key_string'
  ) THEN
    ALTER TABLE activation_keys RENAME COLUMN key_hash TO key_string;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'hmac_sig'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'activation_keys' AND column_name = 'hmac_signature'
  ) THEN
    ALTER TABLE activation_keys RENAME COLUMN hmac_sig TO hmac_signature;
  END IF;

  FOR chk_name IN
    SELECT con.conname
    FROM pg_constraint con
    WHERE con.conrelid = 'activation_keys'::regclass
      AND con.contype = 'c'
  LOOP
    EXECUTE format('ALTER TABLE activation_keys DROP CONSTRAINT %I', chk_name);
  END LOOP;

  FOR fk_name IN
    SELECT con.conname
    FROM pg_constraint con
    WHERE con.conrelid = 'activation_keys'::regclass
      AND con.contype = 'f'
  LOOP
    EXECUTE format('ALTER TABLE activation_keys DROP CONSTRAINT %I', fk_name);
  END LOOP;
END $$;

ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS key_string TEXT;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS reseller_id UUID;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS dealer_id UUID;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS device_id UUID;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS request_id UUID;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS hmac_signature TEXT;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS nonce VARCHAR(64);
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS sig_timestamp BIGINT;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'available';
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS imei_hash TEXT;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS imei BYTEA;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE activation_keys ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE activation_keys ALTER COLUMN status TYPE TEXT USING status::TEXT;
UPDATE activation_keys SET status = LOWER(status);
UPDATE activation_keys SET status = 'revoked' WHERE status IN ('expired', 'suspended');
UPDATE activation_keys SET status = 'available' WHERE status IN ('pending', 'generated', 'approved');
UPDATE activation_keys SET status = 'assigned' WHERE status = 'assigned';
UPDATE activation_keys SET status = 'activated' WHERE status IN ('consumed', 'activated');
UPDATE activation_keys SET status = 'available' WHERE status IS NULL OR status NOT IN ('available', 'assigned', 'activated', 'revoked');
UPDATE activation_keys SET created_at = NOW() WHERE created_at IS NULL;
UPDATE activation_keys SET updated_at = NOW() WHERE updated_at IS NULL;
UPDATE activation_keys SET hmac_signature = COALESCE(hmac_signature, '');
UPDATE activation_keys SET nonce = COALESCE(nonce, '');
UPDATE activation_keys SET sig_timestamp = COALESCE(sig_timestamp, 0);

ALTER TABLE activation_keys ALTER COLUMN status SET DEFAULT 'available';
ALTER TABLE activation_keys ALTER COLUMN status SET NOT NULL;
ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_status_check
  CHECK (status IN ('available', 'assigned', 'activated', 'revoked'));
ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_reseller_id_fkey
  FOREIGN KEY (reseller_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_dealer_id_fkey
  FOREIGN KEY (dealer_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_device_id_fkey
  FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL;
ALTER TABLE activation_keys ADD CONSTRAINT activation_keys_request_id_fkey
  FOREIGN KEY (request_id) REFERENCES key_requests(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_activation_keys_key_string ON activation_keys(key_string);
CREATE INDEX IF NOT EXISTS idx_activation_keys_reseller_status ON activation_keys(reseller_id, status);
CREATE INDEX IF NOT EXISTS idx_activation_keys_dealer_status ON activation_keys(dealer_id, status);
CREATE INDEX IF NOT EXISTS idx_activation_keys_status ON activation_keys(status);

-- ---------------------------------------------------------------------------
-- EMI payments: emi_schedule_id is canonical.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  chk_name TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'schedule_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'emi_schedule_id'
  ) THEN
    ALTER TABLE emi_payments RENAME COLUMN schedule_id TO emi_schedule_id;
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'schedule_id'
  ) THEN
    UPDATE emi_payments SET emi_schedule_id = COALESCE(emi_schedule_id, schedule_id);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'emi_id'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'emi_schedule_id'
  ) THEN
    ALTER TABLE emi_payments RENAME COLUMN emi_id TO emi_schedule_id;
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'emi_payments' AND column_name = 'emi_id'
  ) THEN
    UPDATE emi_payments SET emi_schedule_id = COALESCE(emi_schedule_id, emi_id);
  END IF;

  FOR chk_name IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'emi_payments'::regclass
      AND con.contype = 'c'
      AND att.attname IN ('status', 'payment_status')
  LOOP
    EXECUTE format('ALTER TABLE emi_payments DROP CONSTRAINT %I', chk_name);
  END LOOP;
END $$;

ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS emi_schedule_id UUID REFERENCES emi_schedules(id);
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS method TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS transaction_ref TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS tx_id TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS payment_date TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS recorded_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS installment_number INTEGER;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS note TEXT;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE emi_payments ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES users(id);

ALTER TABLE emi_payments ALTER COLUMN status TYPE TEXT USING status::TEXT;
ALTER TABLE emi_payments ALTER COLUMN payment_status TYPE TEXT USING payment_status::TEXT;
ALTER TABLE emi_payments ALTER COLUMN method TYPE TEXT USING method::TEXT;
ALTER TABLE emi_payments ALTER COLUMN payment_method TYPE TEXT USING payment_method::TEXT;
UPDATE emi_payments SET method = COALESCE(method, payment_method);
UPDATE emi_payments SET payment_method = COALESCE(payment_method, method);
UPDATE emi_payments SET tx_id = COALESCE(tx_id, transaction_ref);
UPDATE emi_payments SET transaction_ref = COALESCE(transaction_ref, tx_id);
UPDATE emi_payments SET status = LOWER(COALESCE(status, payment_status, 'pending'));
UPDATE emi_payments SET payment_status = LOWER(COALESCE(payment_status, status, 'pending'));
UPDATE emi_payments SET recorded_at = COALESCE(recorded_at, payment_date, NOW());
UPDATE emi_payments SET payment_date = COALESCE(payment_date, recorded_at, NOW());

CREATE INDEX IF NOT EXISTS idx_emi_payments_emi_schedule_id ON emi_payments(emi_schedule_id);
CREATE INDEX IF NOT EXISTS idx_emi_payments_device_id ON emi_payments(device_id);
CREATE INDEX IF NOT EXISTS idx_emi_payments_status ON emi_payments(status);
CREATE INDEX IF NOT EXISTS idx_emi_payments_payment_status ON emi_payments(payment_status);

COMMIT;
