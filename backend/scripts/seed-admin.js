/**
 * Admin Seed Script
 * Creates the first admin user directly in the Neon database.
 * Run with: node scripts/seed-admin.js
 */

require('dotenv').config();
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const ADMIN_EMAIL = 'admin@emi-locker.com';
const ADMIN_PASSWORD = 'Admin@123456';
const ADMIN_NAME = 'Super Admin';
const ADMIN_PHONE = '01700000000';

async function seedAdmin() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  const client = await pool.connect();

  try {
    console.log('Connecting to Neon database...');
    await client.query('SELECT 1');
    console.log('✅ Connected successfully.\n');

    // Check if admin already exists
    const existing = await client.query(
      `SELECT id, email, role FROM users WHERE email = $1`,
      [ADMIN_EMAIL.toLowerCase()]
    );

    if (existing.rows.length > 0) {
      const user = existing.rows[0];
      console.log(`⚠️  User already exists: ${user.email} (role: ${user.role})`);

      if (user.role !== 'admin') {
        await client.query(
          `UPDATE users SET role = 'admin', status = 'active', updated_at = NOW() WHERE id = $1`,
          [user.id]
        );
        console.log('✅ Upgraded existing user to admin role.');
      } else {
        console.log('✅ User is already an admin. Nothing to do.');
      }
      return;
    }

    // Hash the password
    console.log('Generating secure password hash...');
    const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, 12);

    // Insert admin user
    const result = await client.query(
      `INSERT INTO users (
        id, email, password_hash, name, phone,
        role, status, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, 'admin', 'active', NOW(), NOW())
      RETURNING id, email, name, role, status`,
      [
        uuidv4(),
        ADMIN_EMAIL.toLowerCase(),
        passwordHash,
        ADMIN_NAME,
        ADMIN_PHONE
      ]
    );

    const admin = result.rows[0];
    console.log('\n✅ Admin user created successfully!');
    console.log('-----------------------------------');
    console.log(`  ID:       ${admin.id}`);
    console.log(`  Email:    ${admin.email}`);
    console.log(`  Name:     ${admin.name}`);
    console.log(`  Role:     ${admin.role}`);
    console.log(`  Status:   ${admin.status}`);
    console.log('-----------------------------------');
    console.log('\n🔑 Login credentials:');
    console.log(`  Email:    ${ADMIN_EMAIL}`);
    console.log(`  Password: ${ADMIN_PASSWORD}`);
    console.log('\n⚠️  IMPORTANT: Change your password after first login!');

  } catch (err) {
    console.error('\n❌ Seed failed:', err.message);
    if (err.message.includes('relation "users" does not exist')) {
      console.error('\n👉 The database schema has not been run yet.');
      console.error('   Please run your migrations first:');
      console.error('   Go to Neon SQL Editor and run the files in database/migrations/ in order.');
    }
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

seedAdmin();
