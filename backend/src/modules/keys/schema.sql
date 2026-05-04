-- EMI Locker Platform - Key Management Schema
-- Run this SQL to create required tables

CREATE TABLE IF NOT EXISTS key_requests (
  id SERIAL PRIMARY KEY,
  reseller_id INTEGER NOT NULL REFERENCES resellers(id),
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  justification TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING_ADMIN',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  approved_by INTEGER REFERENCES admins(id),
  approved_at TIMESTAMP,
  rejected_by INTEGER REFERENCES admins(id),
  rejected_at TIMESTAMP,
  rejection_reason TEXT,
  CONSTRAINT chk_key_request_status CHECK (status IN ('PENDING_ADMIN', 'APPROVED', 'REJECTED'))
);

CREATE TABLE IF NOT EXISTS keys (
  id SERIAL PRIMARY KEY,
  key_string VARCHAR(19) NOT NULL UNIQUE,
  dealer_id INTEGER REFERENCES dealers(id),
  reseller_id INTEGER NOT NULL REFERENCES resellers(id),
  hmac_signature VARCHAR(64) NOT NULL,
  timestamp BIGINT NOT NULL,
  nonce VARCHAR(32) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'GENERATED',
  imei VARCHAR(15),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMP NOT NULL,
  assigned_at TIMESTAMP,
  consumed_at TIMESTAMP,
  expired_at TIMESTAMP,
  request_id INTEGER REFERENCES key_requests(id),
  CONSTRAINT chk_key_status CHECK (status IN ('PENDING_ADMIN', 'GENERATED', 'ASSIGNED', 'CONSUMED', 'EXPIRED', 'REVOKED'))
);

CREATE INDEX idx_keys_reseller_id ON keys(reseller_id);
CREATE INDEX idx_keys_dealer_id ON keys(dealer_id);
CREATE INDEX idx_keys_status ON keys(status);
CREATE INDEX idx_keys_expires_at ON keys(expires_at);
CREATE INDEX idx_keys_key_string ON keys(key_string);

CREATE INDEX idx_key_requests_reseller_id ON key_requests(reseller_id);
CREATE INDEX idx_key_requests_status ON key_requests(status);

CREATE TABLE IF NOT EXISTS audit_logs (
  id SERIAL PRIMARY KEY,
  user_id INTEGER,
  action VARCHAR(50) NOT NULL,
  metadata JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);