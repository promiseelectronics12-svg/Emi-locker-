-- Migration: 012_lock_module.sql
-- Description: Lock engine tables — PADT tokens, escalations, delivery log, grace periods, device locations
-- Adds columns to devices and lock_requests for lock engine integration

-- PADT (Pre-Authorized Decouple Token) table
CREATE TABLE padt_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jti             UUID NOT NULL UNIQUE,
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    imei            TEXT NOT NULL,
    owner_id        UUID,
    dealer_id       UUID,
    token_hash       TEXT NOT NULL,
    issued_at       TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    used            BOOLEAN NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    revoked         BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_padt_tokens_jti ON padt_tokens (jti);
CREATE INDEX idx_padt_tokens_device_id ON padt_tokens (device_id);
CREATE INDEX idx_padt_tokens_expires_at ON padt_tokens (expires_at);
CREATE INDEX idx_padt_tokens_used ON padt_tokens (used);

-- Admin escalations for SUSPECTED_FRAUD, SUSPECTED_SALE, and extended overdue
CREATE TABLE admin_escalations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type     TEXT NOT NULL CHECK (entity_type IN ('device', 'dealer', 'user')),
    entity_id       UUID NOT NULL,
    dealer_id       UUID,
    reason          TEXT NOT NULL,
    note            TEXT,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
    reviewed_by     UUID,
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_escalations_entity ON admin_escalations (entity_type, entity_id);
CREATE INDEX idx_admin_escalations_status ON admin_escalations (status);
CREATE INDEX idx_admin_escalations_created ON admin_escalations (created_at);

-- Lock delivery log — tracks FCM, AMAPI, PAUT delivery results
CREATE TABLE lock_delivery_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    command_nonce   TEXT NOT NULL,
    command_type    TEXT NOT NULL,
    fcm_result      JSONB,
    amapi_result    JSONB,
    paut_result     JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lock_delivery_log_device_id ON lock_delivery_log (device_id);
CREATE INDEX idx_lock_delivery_log_created ON lock_delivery_log (created_at);

-- Grace period extensions — dealer or admin can grant extra time
CREATE TABLE grace_period_extensions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    granted_by      UUID NOT NULL,
    granted_until   TIMESTAMPTZ NOT NULL,
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'revoked')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_grace_period_extensions_device ON grace_period_extensions (device_id);
CREATE INDEX idx_grace_period_extensions_status ON grace_period_extensions (status);

-- Device GPS locations — for dealer shop proximity check
CREATE TABLE device_locations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE RESTRICT,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    accuracy        DOUBLE PRECISION,
    recorded_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_device_locations_device_id ON device_locations (device_id);
CREATE INDEX idx_device_locations_recorded ON device_locations (recorded_at);

-- Add lock_level column to devices if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'lock_level') THEN
        ALTER TABLE devices ADD COLUMN lock_level TEXT DEFAULT 'NONE';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'lock_reason') THEN
        ALTER TABLE devices ADD COLUMN lock_reason TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'locked_at') THEN
        ALTER TABLE devices ADD COLUMN locked_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'devices' AND column_name = 'locked_by') THEN
        ALTER TABLE devices ADD COLUMN locked_by UUID;
    END IF;
END $$;

-- Add decision and rejection_reasons columns to lock_requests if needed
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'lock_requests' AND column_name = 'decision') THEN
        ALTER TABLE lock_requests ADD COLUMN decision TEXT CHECK (decision IN ('APPROVED', 'REJECTED', 'ESCALATED'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'lock_requests' AND column_name = 'rejection_reasons') THEN
        ALTER TABLE lock_requests ADD COLUMN rejection_reasons JSONB;
    END IF;
END $$;

-- Add shop location columns to dealers table if not exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dealers') THEN
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'dealers' AND column_name = 'shop_latitude') THEN
            ALTER TABLE dealers ADD COLUMN shop_latitude DOUBLE PRECISION;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'dealers' AND column_name = 'shop_longitude') THEN
            ALTER TABLE dealers ADD COLUMN shop_longitude DOUBLE PRECISION;
        END IF;
    END IF;
END $$;
