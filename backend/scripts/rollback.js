const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function rollback() {
  const client = await pool.connect();

  try {
    console.log('Starting database rollback...');

    await client.query('BEGIN');

    await client.query('DROP FUNCTION IF EXISTS get_upcoming_emi_installments(INTEGER, TIMESTAMP);');
    await client.query('DROP FUNCTION IF EXISTS calculate_due_dates(UUID, DATE, DECIMAL, INTEGER);');
    await client.query('DROP FUNCTION IF EXISTS generate_installments(UUID, DECIMAL, DECIMAL, INTEGER);');

    await client.query('DROP TABLE IF EXISTS notifications;');
    await client.query('DROP TABLE IF EXISTS device_locations;');
    await client.query('DROP TABLE IF EXISTS security_events;');
    await client.query('DROP TABLE IF EXISTS audit_log;');
    await client.query('DROP TABLE IF EXISTS padt_tokens;');
    await client.query('DROP TABLE IF EXISTS paut_tokens;');
    await client.query('DROP TABLE IF EXISTS admin_escalations;');
    await client.query('DROP TABLE IF EXISTS grace_period_extensions;');
    await client.query('DROP TABLE IF EXISTS grace_period_requests;');
    await client.query('DROP TABLE IF EXISTS lock_delivery_log;');
    await client.query('DROP TABLE IF EXISTS lock_requests;');
    await client.query('DROP TABLE IF EXISTS decoupling_state_log;');
    await client.query('DROP TABLE IF EXISTS decoupling_state;');
    await client.query('DROP TABLE IF EXISTS emi_payments;');
    await client.query('DROP TABLE IF EXISTS emi_schedules;');
    await client.query('DROP TABLE IF EXISTS enrollment_tokens;');
    await client.query('DROP TABLE IF EXISTS devices;');
    await client.query('DROP TABLE IF EXISTS dealers;');
    await client.query('DROP TABLE IF EXISTS users;');

    await client.query('COMMIT');
    console.log('Rollback completed successfully.');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Rollback failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

rollback().catch(err => {
  console.error(err);
  process.exit(1);
});