-- Migration: 001_users.sql
-- Description: Users table for authentication and role management
-- Sensitive fields (email, phone, totp_secret) encrypted at rest with AES-256
-- via application-level encryption before INSERT/UPDATE

-- ENUM for user roles
CREATE TYPE user_role AS ENUM ('admin', 'reseller', 'dealer', 'customer');

-- ENUM for user status
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'suspended', 'pending_verification');

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- email: AES-256 encrypted at rest, stored as BYTEA
    email           BYTEA NOT NULL,
    -- email_hash: SHA-256 of lowercase plaintext email for uniqueness enforcement
    email_hash      TEXT NOT NULL,
    -- phone: AES-256 encrypted at rest, stored as BYTEA
    phone           BYTEA NOT NULL,
    -- phone_hash: SHA-256 of plaintext phone for uniqueness enforcement
    phone_hash      TEXT,
    role            user_role NOT NULL DEFAULT 'customer',
    -- password_hash: bcrypt/argon2 hash, NOT reversible
    password_hash   TEXT NOT NULL,
    -- totp_secret: AES-256 encrypted at rest, stored as BYTEA
    totp_secret     BYTEA,
    status          user_status NOT NULL DEFAULT 'pending_verification',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique index on email hash for application-level uniqueness enforcement
CREATE UNIQUE INDEX idx_users_email_hash ON users (email_hash);
CREATE INDEX idx_users_role ON users (role);
CREATE INDEX idx_users_status ON users (status);
CREATE INDEX idx_users_created_at ON users (created_at);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_users_updated_at();
