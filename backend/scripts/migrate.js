require('dotenv').config();
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function migrate() {
  const client = await pool.connect();

  try {
    console.log('Starting database migration...');

    await client.query('BEGIN');

    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255),
        name VARCHAR(255),
        nid VARCHAR(50),
        phone VARCHAR(50),
        address TEXT,
        role VARCHAR(50) DEFAULT 'customer',
        status VARCHAR(50) DEFAULT 'active',
        totp_secret VARCHAR(255),
        totp_enabled BOOLEAN DEFAULT FALSE,
        totp_pending BOOLEAN DEFAULT FALSE,
        backup_codes JSONB,
        last_login TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
      CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
      CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS dealers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        phone VARCHAR(50),
        address TEXT,
        shop_latitude DECIMAL(10, 8),
        shop_longitude DECIMAL(11, 8),
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_dealers_email ON dealers(email);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS devices (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        amapi_device_name VARCHAR(500),
        amapi_device_id VARCHAR(255),
        imei VARCHAR(50) UNIQUE NOT NULL,
        serial_number VARCHAR(100),
        soc_id VARCHAR(100),
        managed_google_account VARCHAR(255),
        dealer_id UUID REFERENCES dealers(id),
        owner_id UUID REFERENCES users(id),
        device_name VARCHAR(255),
        model VARCHAR(255),
        brand VARCHAR(255),
        enrollment_token VARCHAR(500),
        fcm_token TEXT,
        fcm_token_updated_at TIMESTAMP,
        imei_encrypted TEXT,
        imei_hash VARCHAR(255),
        status VARCHAR(50) DEFAULT 'active',
        lock_level INTEGER DEFAULT 0,
        unlock_code_hash VARCHAR(255),
        unlock_code_salt VARCHAR(255),
        policy_last_applied TIMESTAMP,
        enrolled_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

CREATE INDEX IF NOT EXISTS idx_devices_imei_encrypted ON devices(imei_encrypted);
    CREATE INDEX IF NOT EXISTS idx_devices_imei_hash ON devices(imei_hash);
    CREATE INDEX IF NOT EXISTS idx_devices_dealer_id ON devices(dealer_id);
      CREATE INDEX IF NOT EXISTS idx_devices_owner_id ON devices(owner_id);
      CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS enrollment_tokens (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        token VARCHAR(500) UNIQUE NOT NULL,
        dealer_id UUID REFERENCES dealers(id),
        expires_at TIMESTAMP,
        used BOOLEAN DEFAULT FALSE,
        used_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_enrollment_tokens_token ON enrollment_tokens(token);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS emi_schedules (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        total_amount DECIMAL(15, 2) NOT NULL,
        down_payment DECIMAL(15, 2) DEFAULT 0,
        emi_amount DECIMAL(15, 2) NOT NULL,
        duration INTEGER NOT NULL,
        start_date DATE NOT NULL,
        grace_days INTEGER DEFAULT 7,
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_emi_schedules_device_id ON emi_schedules(device_id);
      CREATE INDEX IF NOT EXISTS idx_emi_schedules_status ON emi_schedules(status);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS emi_payments (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        schedule_id UUID REFERENCES emi_schedules(id),
        device_id UUID REFERENCES devices(id),
        amount DECIMAL(15, 2) NOT NULL,
        method VARCHAR(50),
        tx_id VARCHAR(255),
        installment_number INTEGER,
        note TEXT,
        status VARCHAR(50) DEFAULT 'pending',
        recorded_at TIMESTAMP DEFAULT NOW(),
        verified_at TIMESTAMP,
        verified_by UUID REFERENCES users(id)
      );

      CREATE INDEX IF NOT EXISTS idx_emi_payments_schedule_id ON emi_payments(schedule_id);
      CREATE INDEX IF NOT EXISTS idx_emi_payments_device_id ON emi_payments(device_id);
      CREATE INDEX IF NOT EXISTS idx_emi_payments_status ON emi_payments(status);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS decoupling_state (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id) UNIQUE,
        schedule_id UUID REFERENCES emi_schedules(id),
        state VARCHAR(50) DEFAULT 'EMI_ACTIVE',
        dealer_notified_at TIMESTAMP,
        fraud_flag BOOLEAN DEFAULT FALSE,
        fraud_flagged_by UUID,
        fraud_flagged_at TIMESTAMP,
        fraud_reason TEXT,
        fraud_window_started_at TIMESTAMP,
        fraud_window_ends_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_decoupling_state_device_id ON decoupling_state(device_id);
      CREATE INDEX IF NOT EXISTS idx_decoupling_state_state ON decoupling_state(state);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS decoupling_state_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        from_state VARCHAR(50),
        to_state VARCHAR(50),
        metadata JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_decoupling_state_log_device_id ON decoupling_state_log(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS lock_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        dealer_id UUID REFERENCES dealers(id),
        requested_by UUID REFERENCES users(id),
        device_id UUID REFERENCES devices(id),
        reason_code VARCHAR(50),
        note TEXT,
        status VARCHAR(50) DEFAULT 'pending',
        rejection_reasons JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_lock_requests_dealer_id ON lock_requests(dealer_id);
      CREATE INDEX IF NOT EXISTS idx_lock_requests_device_id ON lock_requests(device_id);
      CREATE INDEX IF NOT EXISTS idx_lock_requests_status ON lock_requests(status);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS lock_delivery_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        command_nonce VARCHAR(100),
        command_type VARCHAR(50),
        fcm_result JSONB,
        amapi_result JSONB,
        paut_result JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_lock_delivery_log_device_id ON lock_delivery_log(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS grace_period_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        schedule_id UUID REFERENCES emi_schedules(id),
        reason TEXT,
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_grace_period_requests_device_id ON grace_period_requests(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS grace_period_extensions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        granted_until TIMESTAMP,
        reason TEXT,
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_grace_period_extensions_device_id ON grace_period_extensions(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS admin_escalations (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        entity_type VARCHAR(50),
        entity_id UUID,
        dealer_id UUID REFERENCES dealers(id),
        reason TEXT,
        note TEXT,
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_admin_escalations_entity ON admin_escalations(entity_type, entity_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS paut_tokens (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        jti VARCHAR(255) UNIQUE NOT NULL,
        device_id UUID REFERENCES devices(id),
        imei VARCHAR(50) NOT NULL,
        lock_level VARCHAR(50) NOT NULL,
        token_hash VARCHAR(255),
        issued_at TIMESTAMP,
        expires_at TIMESTAMP NOT NULL,
        used BOOLEAN DEFAULT FALSE,
        used_at TIMESTAMP,
        revoked BOOLEAN DEFAULT FALSE,
        revoked_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_paut_tokens_jti ON paut_tokens(jti);
      CREATE INDEX IF NOT EXISTS idx_paut_tokens_device_id ON paut_tokens(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS padt_tokens (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        jti VARCHAR(255) UNIQUE NOT NULL,
        device_id UUID REFERENCES devices(id),
        imei VARCHAR(50),
        owner_id UUID,
        dealer_id UUID,
        token_hash VARCHAR(255),
        expires_at TIMESTAMP NOT NULL,
        used BOOLEAN DEFAULT FALSE,
        used_at TIMESTAMP,
        revoked BOOLEAN DEFAULT FALSE,
        revoked_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_padt_tokens_jti ON padt_tokens(jti);
      CREATE INDEX IF NOT EXISTS idx_padt_tokens_device_id ON padt_tokens(device_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS audit_log (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        actor VARCHAR(255),
        actor_type VARCHAR(50),
        action VARCHAR(100) NOT NULL,
        device_id UUID REFERENCES devices(id),
        metadata JSONB,
        ip_address VARCHAR(50),
        result VARCHAR(50) DEFAULT 'success',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor);
      CREATE INDEX IF NOT EXISTS idx_audit_log_device_id ON audit_log(device_id);
      CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action);
      CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS security_events (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        event_type VARCHAR(100) NOT NULL,
        severity VARCHAR(50) DEFAULT 'info',
        actor VARCHAR(255),
        device_id UUID REFERENCES devices(id),
        metadata JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);
      CREATE INDEX IF NOT EXISTS idx_security_events_device_id ON security_events(device_id);
      CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS location_reports (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        accuracy DECIMAL(10, 2) NOT NULL,
        timestamp TIMESTAMPTZ NOT NULL,
        battery_level INTEGER,
        pull_id VARCHAR(255),
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_location_reports_device_id ON location_reports(device_id);
      CREATE INDEX IF NOT EXISTS idx_location_reports_timestamp ON location_reports(timestamp DESC);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS location_pull_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        pull_id VARCHAR(255) UNIQUE NOT NULL,
        reason VARCHAR(255) NOT NULL,
        requested_by UUID REFERENCES users(id),
        status VARCHAR(50) DEFAULT 'pending',
        requested_at TIMESTAMPTZ DEFAULT NOW(),
        responded_at TIMESTAMPTZ,
        expires_at TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_location_pull_requests_device_id ON location_pull_requests(device_id);
      CREATE INDEX IF NOT EXISTS idx_location_pull_requests_status ON location_pull_requests(status);
      CREATE INDEX IF NOT EXISTS idx_location_pull_requests_pull_id ON location_pull_requests(pull_id);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS geofences (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        name VARCHAR(100) NOT NULL,
        type VARCHAR(50) NOT NULL CHECK (type IN ('circle', 'polygon')),
        center_latitude DECIMAL(10, 8),
        center_longitude DECIMAL(11, 8),
        radius_meters INTEGER,
        coordinates JSONB,
        enabled BOOLEAN DEFAULT true,
        created_by UUID REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_geofences_device_id ON geofences(device_id);
      CREATE INDEX IF NOT EXISTS idx_geofences_enabled ON geofences(enabled);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS geofence_alerts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
        geofence_id UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
        alert_id VARCHAR(255) UNIQUE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        triggered_at TIMESTAMPTZ DEFAULT NOW(),
        acknowledged BOOLEAN DEFAULT false,
        acknowledged_at TIMESTAMPTZ,
        acknowledged_by UUID REFERENCES users(id),
        created_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_geofence_alerts_device_id ON geofence_alerts(device_id);
      CREATE INDEX IF NOT EXISTS idx_geofence_alerts_alert_id ON geofence_alerts(alert_id);
      CREATE INDEX IF NOT EXISTS idx_geofence_alerts_acknowledged ON geofence_alerts(acknowledged);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS alerts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        dealer_id UUID REFERENCES users(id),
        device_id UUID REFERENCES devices(id) ON DELETE CASCADE,
        alert_type VARCHAR(100) NOT NULL,
        title VARCHAR(255) NOT NULL,
        message TEXT,
        metadata JSONB,
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_alerts_dealer_id ON alerts(dealer_id);
      CREATE INDEX IF NOT EXISTS idx_alerts_device_id ON alerts(device_id);
      CREATE INDEX IF NOT EXISTS idx_alerts_status ON alerts(status);
      CREATE INDEX IF NOT EXISTS idx_alerts_created_at ON alerts(created_at DESC);
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS notifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        device_id UUID REFERENCES devices(id),
        type VARCHAR(50) NOT NULL,
        title VARCHAR(255),
        body TEXT,
        payload JSONB,
        status VARCHAR(50) DEFAULT 'PENDING',
        fcm_message_id VARCHAR(255),
        provider VARCHAR(50),
        delivered_at TIMESTAMP,
        failed_at TIMESTAMP,
        failure_reason TEXT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_notifications_device_id ON notifications(device_id);
      CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status);
      CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
    `);

    await client.query(`
      CREATE OR REPLACE FUNCTION generate_installments(p_device_id UUID, p_total_amount DECIMAL, p_emi_amount DECIMAL, p_duration INTEGER)
      RETURNS TABLE(
        schedule_id UUID,
        installment_number INTEGER,
        amount DECIMAL,
        due_date DATE
      ) AS $$
      DECLARE
        v_start_date DATE;
        v_grace_days INTEGER;
      BEGIN
        SELECT start_date, grace_days INTO v_start_date, v_grace_days
        FROM emi_schedules
        WHERE device_id = p_device_id AND status = 'active'
        ORDER BY created_at DESC LIMIT 1;

        FOR i IN 1..p_duration LOOP
          schedule_id := p_device_id;
          installment_number := i;
          amount := p_emi_amount;
          due_date := v_start_date + ((i - 1) || ' months')::INTERVAL;
          RETURN NEXT;
        END LOOP;
      END;
      $$ LANGUAGE plpgsql;
    `);

    await client.query(`
      CREATE OR REPLACE FUNCTION calculate_due_dates(p_device_id UUID, p_start_date DATE, p_emi_amount DECIMAL, p_duration INTEGER)
      RETURNS TABLE(due_date DATE) AS $$
      DECLARE
        i INTEGER;
      BEGIN
        FOR i IN 1..p_duration LOOP
          due_date := p_start_date + ((i) || ' months')::INTERVAL;
          RETURN NEXT;
        END LOOP;
      END;
      $$ LANGUAGE plpgsql;
    `);

    await client.query(`
      CREATE OR REPLACE FUNCTION get_upcoming_emi_installments(p_days INTEGER, p_from_date TIMESTAMP)
      RETURNS TABLE(device_id UUID, next_due_date DATE, amount DECIMAL) AS $$
      BEGIN
        RETURN QUERY
        SELECT
          es.device_id,
          (es.start_date + (generate_series(1, es.duration) || ' months')::INTERVAL)::DATE as next_due_date,
          es.emi_amount
        FROM emi_schedules es
        WHERE es.status = 'active'
          AND (es.start_date + (generate_series(1, es.duration) || ' months')::INTERVAL)::DATE
            BETWEEN p_from_date::DATE AND (p_from_date::DATE + p_days)
        ORDER BY next_due_date;
      END;
      $$ LANGUAGE plpgsql;
    `);

    await client.query('COMMIT');
    console.log('Migration completed successfully.');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Migration failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

migrate().catch(err => {
  console.error(err);
  process.exit(1);
});