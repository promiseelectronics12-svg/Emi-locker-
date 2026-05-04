-- ============================================================
-- Decoupling Module Schema
-- ============================================================
-- State machine:
--   EMI_ACTIVE → FINAL_PAYMENT_RECEIVED → DEALER_NOTIFIED
--     → (no fraud) → PENDING_ADMIN_DECOUPLE → DEVICE_DECOUPLED
--     → (fraud) FRAUD_FLAGGED → FRAUD_CONFIRMED | FRAUD_REJECTED
--       FRAUD_REJECTED → PENDING_ADMIN_DECOUPLE → DEVICE_DECOUPLED
-- ============================================================

CREATE TYPE decoupling_state_enum AS ENUM (
  'EMI_ACTIVE',
  'FINAL_PAYMENT_RECEIVED',
  'DEALER_NOTIFIED',
  'FRAUD_FLAGGED',
  'FRAUD_CONFIRMED',
  'FRAUD_REJECTED',
  'PENDING_ADMIN_DECOUPLE',
  'DEVICE_DECOUPLED'
);

CREATE TABLE IF NOT EXISTS decoupling (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID NOT NULL REFERENCES devices(id),
  emi_schedule_id UUID REFERENCES emi_schedules(id),
  state decoupling_state_enum NOT NULL DEFAULT 'EMI_ACTIVE',

  -- Fraud window tracking
  dealer_notified_at TIMESTAMPTZ,
  fraud_window_started_at TIMESTAMPTZ,
  fraud_window_ends_at TIMESTAMPTZ,

  -- Fraud flag (dealer can flag, cannot block)
  fraud_flag BOOLEAN DEFAULT false,
  fraud_flagged_by UUID REFERENCES users(id),
  fraud_flagged_at TIMESTAMPTZ,
  fraud_reason TEXT,
  fraud_evidence_url TEXT,
  fraud_confirmed_by UUID REFERENCES users(id),
  fraud_confirmed_at TIMESTAMPTZ,
  fraud_rejected_by UUID REFERENCES users(id),
  fraud_rejected_at TIMESTAMPTZ,

  -- RTOC (Release Token One-time Code)
  rtoc_code_hash TEXT,
  rtoc_generated_at TIMESTAMPTZ,
  rtoc_generated_by UUID REFERENCES users(id),

  -- Admin 2FA verification
  admin_action_by UUID REFERENCES users(id),
  admin_action_at TIMESTAMPTZ,
  admin_2fa_verified BOOLEAN DEFAULT false,

  -- FCM delivery tracking
  fcm_sent_at TIMESTAMPTZ,
  fcm_delivered BOOLEAN,
  fcm_failure_reason TEXT,

  -- PADT fallback (Pre-Authorized Decouple Token, 7-day expiry)
  padt_token_id UUID,
  padt_issued_at TIMESTAMPTZ,
  padt_expires_at TIMESTAMPTZ,

  -- AMAPI deletion tracking
  amapi_deleted_at TIMESTAMPTZ,
  amapi_delete_success BOOLEAN,
  amapi_deletion_status TEXT DEFAULT 'pending' CHECK (amapi_deletion_status IN ('pending', 'completed', 'failed_retrying', 'failed_permanent')),

  -- Final decoupling
  decoupled_at TIMESTAMPTZ,
  decoupled_by UUID REFERENCES users(id),

  -- Auto admin notification timer
  auto_notify_admin_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT unique_device_decoupling UNIQUE (device_id)
);

-- Primary lookup indexes
CREATE INDEX IF NOT EXISTS idx_decoupling_state ON decoupling(state);
CREATE INDEX IF NOT EXISTS idx_decoupling_device ON decoupling(device_id);

-- Fraud window expiration scan (only active windows)
CREATE INDEX IF NOT EXISTS idx_decoupling_fraud_window
  ON decoupling(fraud_window_ends_at)
  WHERE state = 'DEALER_NOTIFIED';

-- Auto admin notification scan (only unf-flagged devices past window)
CREATE INDEX IF NOT EXISTS idx_decoupling_auto_notify
  ON decoupling(auto_notify_admin_at)
  WHERE state = 'DEALER_NOTIFIED' AND fraud_flag = false;

-- ============================================================
-- Immutable audit log — every state transition is recorded
-- ============================================================
CREATE TABLE IF NOT EXISTS decoupling_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decoupling_id UUID NOT NULL REFERENCES decoupling(id),
  device_id UUID NOT NULL REFERENCES devices(id),
  from_state decoupling_state_enum,
  to_state decoupling_state_enum NOT NULL,
  actor_id UUID REFERENCES users(id),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('system', 'admin', 'dealer', 'scheduler')),
  action TEXT NOT NULL,
  details_json JSONB DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_decoupling_audit_device ON decoupling_audit_log(device_id);
CREATE INDEX IF NOT EXISTS idx_decoupling_audit_decoupling ON decoupling_audit_log(decoupling_id);
CREATE INDEX IF NOT EXISTS idx_decoupling_audit_created ON decoupling_audit_log(created_at);

-- ============================================================
-- Immutable audit log trigger functions
-- ============================================================
CREATE OR REPLACE FUNCTION prevent_audit_log_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are immutable and cannot be updated';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_audit_log_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are immutable and cannot be deleted';
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_decoupling_audit_no_update'
  ) THEN
    CREATE TRIGGER trg_decoupling_audit_no_update
      BEFORE UPDATE ON decoupling_audit_log
      FOR EACH ROW
      EXECUTE FUNCTION prevent_audit_log_update();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_decoupling_audit_no_delete'
  ) THEN
    CREATE TRIGGER trg_decoupling_audit_no_delete
      BEFORE DELETE ON decoupling_audit_log
      FOR EACH ROW
      EXECUTE FUNCTION prevent_audit_log_delete();
  END IF;
END $$;

-- ============================================================
-- Auto-update updated_at timestamp on decoupling row changes
-- ============================================================
CREATE OR REPLACE FUNCTION update_decoupling_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_decoupling_updated_at'
  ) THEN
    CREATE TRIGGER trigger_decoupling_updated_at
      BEFORE UPDATE ON decoupling
      FOR EACH ROW
      EXECUTE FUNCTION update_decoupling_updated_at();
  END IF;
END $$;
