require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../src/config/database');

async function migrateAdminPrototype() {
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    await client.query(`
      ALTER TABLE dealers ADD COLUMN IF NOT EXISTS reseller_id UUID;
      CREATE INDEX IF NOT EXISTS idx_dealers_reseller_id ON dealers(reseller_id);

      ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS target_type VARCHAR(50);
      ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS target_id VARCHAR(255);
      CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_type, target_id);

      ALTER TABLE security_events ADD COLUMN IF NOT EXISTS ip_address INET;
      ALTER TABLE security_events ADD COLUMN IF NOT EXISTS resolved BOOLEAN DEFAULT FALSE;
      ALTER TABLE security_events ADD COLUMN IF NOT EXISTS resolved_by UUID REFERENCES users(id);
      ALTER TABLE security_events ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP;

      ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_reason TEXT;
      ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_by UUID;
      ALTER TABLE devices ADD COLUMN IF NOT EXISTS locked_at TIMESTAMP;
      ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_hash VARCHAR(255);
      ALTER TABLE devices ADD COLUMN IF NOT EXISTS unlock_code_salt VARCHAR(255);
      ALTER TABLE devices ADD COLUMN IF NOT EXISTS policy_last_applied TIMESTAMP;
      ALTER TABLE devices ALTER COLUMN lock_level DROP DEFAULT;
      ALTER TABLE devices ALTER COLUMN lock_level TYPE VARCHAR(50) USING COALESCE(lock_level::text, 'NONE');
      ALTER TABLE devices ALTER COLUMN lock_level SET DEFAULT 'NONE';
    `);

    const adminSchema = fs.readFileSync(
      path.join(__dirname, '..', 'src', 'modules', 'admin', 'schema.sql'),
      'utf8',
    );

    const safeAdminSchema = adminSchema
      .replace(/CREATE TABLE IF NOT EXISTS audit_log[\s\S]*?CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log\(created_at DESC\);/m, '')
      .replace(/CREATE TABLE IF NOT EXISTS security_events[\s\S]*?CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events\(created_at DESC\);/m, '')
      .replace(/ALTER TABLE devices ADD COLUMN IF NOT EXISTS lock_level[\s\S]*?;\r?\n?/m, '');

    await client.query(safeAdminSchema);

    await client.query(`
      ALTER TABLE resellers ADD COLUMN IF NOT EXISTS monthly_quota INTEGER DEFAULT 100;
      ALTER TABLE resellers ADD COLUMN IF NOT EXISTS used_keys INTEGER DEFAULT 0;
      ALTER TABLE resellers ADD COLUMN IF NOT EXISTS business_name VARCHAR(255);

      ALTER TABLE key_requests DROP CONSTRAINT IF EXISTS key_requests_status_check;
      ALTER TABLE key_requests ALTER COLUMN status SET DEFAULT 'pending';

      CREATE TABLE IF NOT EXISTS keys (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        key_string VARCHAR(32) UNIQUE NOT NULL,
        dealer_id UUID REFERENCES dealers(id),
        reseller_id UUID NOT NULL REFERENCES resellers(id),
        status VARCHAR(50) DEFAULT 'approved',
        signature TEXT,
        signature_timestamp BIGINT,
        hmac_signature TEXT,
        timestamp BIGINT,
        nonce VARCHAR(255),
        assigned_at TIMESTAMP,
        consumed_at TIMESTAMP,
        expires_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_keys_reseller_id ON keys(reseller_id);
      CREATE INDEX IF NOT EXISTS idx_keys_dealer_id ON keys(dealer_id);
      CREATE INDEX IF NOT EXISTS idx_keys_status ON keys(status);
    `);

    await client.query('COMMIT');
    console.log('Admin prototype migration completed.');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Admin prototype migration failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

migrateAdminPrototype().catch(() => process.exit(1));
