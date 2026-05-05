-- EMI Locker Platform - Canonical Key Management Schema
-- Superseded in deployments by database/migrations/099_unify_schema.sql.

CREATE TABLE IF NOT EXISTS key_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reseller_id UUID NOT NULL REFERENCES resellers(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  justification TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_quantity INTEGER,
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  rejected_by UUID REFERENCES users(id),
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activation_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_string TEXT NOT NULL UNIQUE,
  reseller_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  dealer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
  request_id UUID REFERENCES key_requests(id) ON DELETE SET NULL,
  hmac_signature TEXT NOT NULL,
  nonce VARCHAR(64) NOT NULL,
  sig_timestamp BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'assigned', 'activated', 'revoked')),
  imei_hash TEXT,
  assigned_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activation_keys_reseller_status ON activation_keys(reseller_id, status);
CREATE INDEX IF NOT EXISTS idx_activation_keys_dealer_status ON activation_keys(dealer_id, status);
CREATE INDEX IF NOT EXISTS idx_key_requests_reseller_id ON key_requests(reseller_id);
CREATE INDEX IF NOT EXISTS idx_key_requests_status ON key_requests(status);
