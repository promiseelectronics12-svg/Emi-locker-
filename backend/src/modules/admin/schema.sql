CREATE TABLE IF NOT EXISTS resellers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    company_name VARCHAR(255),
    address TEXT,
    region VARCHAR(100),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'suspended', 'rejected')),
    monthly_key_quota INTEGER DEFAULT 100,
    approved_at TIMESTAMP,
    approved_by UUID REFERENCES users(id),
    rejected_at TIMESTAMP,
    rejected_by UUID REFERENCES users(id),
    rejection_reason TEXT,
    suspended_at TIMESTAMP,
    suspended_by UUID REFERENCES users(id),
    suspension_reason TEXT,
    quota_updated_at TIMESTAMP,
    quota_updated_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS key_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reseller_id UUID NOT NULL REFERENCES resellers(id),
    quantity INTEGER NOT NULL,
    justification TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_quantity INTEGER,
    approved_by UUID REFERENCES users(id),
    approved_at TIMESTAMP,
    rejected_by UUID REFERENCES users(id),
    rejected_at TIMESTAMP,
    rejection_reason TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor VARCHAR(255) NOT NULL,
    action VARCHAR(255) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(255),
    metadata JSONB,
    ip_address INET,
    result VARCHAR(50) DEFAULT 'success' CHECK (result IN ('success', 'failed', 'error')),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at DESC);

CREATE TABLE IF NOT EXISTS security_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type VARCHAR(255) NOT NULL,
    severity VARCHAR(50) DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    actor VARCHAR(255),
    metadata JSONB,
    ip_address INET,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_by UUID REFERENCES users(id),
    resolved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON security_events(severity);
CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at DESC);

CREATE TABLE IF NOT EXISTS neir_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id),
    imei VARCHAR(50) NOT NULL,
    model VARCHAR(255),
    brand VARCHAR(255),
    reason TEXT NOT NULL,
    reported_by UUID NOT NULL REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'submitted', 'confirmed', 'rejected')),
    submitted_at TIMESTAMP,
    submitted_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_neir_queue_status ON neir_queue(status);
CREATE INDEX IF NOT EXISTS idx_neir_queue_device_id ON neir_queue(device_id);
CREATE INDEX IF NOT EXISTS idx_neir_queue_created_at ON neir_queue(created_at DESC);

CREATE TABLE IF NOT EXISTS admin_action_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_id UUID NOT NULL REFERENCES users(id),
    action VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    path TEXT NOT NULL,
    status_code INTEGER,
    duration_ms INTEGER,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_action_log_admin_id ON admin_action_log(admin_id);
CREATE INDEX IF NOT EXISTS idx_admin_action_log_created_at ON admin_action_log(created_at DESC);

ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_verified_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_2fa_verified_at TIMESTAMP;

ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_reason TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES users(id);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_at TIMESTAMP;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level VARCHAR(50) CHECK (lock_level IN ('soft', 'hard', 'wipe'));
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_hash VARCHAR(255);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_salt VARCHAR(255);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS fcm_token_updated_at TIMESTAMP;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS policy_last_applied TIMESTAMP;