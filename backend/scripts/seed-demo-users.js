require('dotenv').config();

const bcrypt = require('bcryptjs');
const db = require('../src/config/database');

const PASSWORD = process.env.DEMO_PASSWORD || 'Demo@123456';
const BCRYPT_ROUNDS = parseInt(process.env.BCRYPT_ROUNDS || '12', 10);

async function ensureDealerUserIdColumn() {
  await db.query('ALTER TABLE dealers ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE');
  await db.query('ALTER TABLE dealers ADD COLUMN IF NOT EXISTS business_name TEXT');
  await db.query('CREATE UNIQUE INDEX IF NOT EXISTS idx_dealers_user_id ON dealers(user_id) WHERE user_id IS NOT NULL');
}

async function upsertUser(client, { email, role, name, phone }) {
  const passwordHash = await bcrypt.hash(PASSWORD, BCRYPT_ROUNDS);
  const existing = await client.query(
    'SELECT id FROM users WHERE LOWER(email) = LOWER($1) ORDER BY created_at ASC LIMIT 1',
    [email]
  );

  if (existing.rows.length > 0) {
    const result = await client.query(
      `UPDATE users
       SET password_hash = $2,
           name = $3,
           phone = $4,
           role = $5,
           status = 'active',
           updated_at = NOW()
       WHERE id = $1
       RETURNING id, email, role, status`,
      [existing.rows[0].id, passwordHash, name, phone, role]
    );
    return result.rows[0];
  }

  const result = await client.query(
    `INSERT INTO users (email, password_hash, name, phone, role, status, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, 'active', NOW(), NOW())
     RETURNING id, email, role, status`,
    [email, passwordHash, name, phone, role]
  );
  return result.rows[0];
}

async function upsertReseller(client, user) {
  const existing = await client.query(
    'SELECT id FROM resellers WHERE id = $1 OR LOWER(email) = LOWER($2) LIMIT 1',
    [user.id, user.email]
  );
  if (existing.rows.length > 0) {
    await client.query(
      `UPDATE resellers
       SET name = $2, email = $3, phone = $4, company_name = $5, business_name = $5,
           address = $6, status = 'active', updated_at = NOW()
       WHERE id = $1`,
      [existing.rows[0].id, 'Demo Reseller', user.email, '+8801700000001', 'Demo Reseller Company', 'Demo Reseller Address']
    );
    return;
  }

  await client.query(
    `INSERT INTO resellers (id, name, email, phone, company_name, business_name, address, status, monthly_key_quota, monthly_quota, used_keys, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $5, $6, 'active', 100, 100, 0, NOW(), NOW())`,
    [user.id, 'Demo Reseller', user.email, '+8801700000001', 'Demo Reseller Company', 'Demo Reseller Address']
  );
}

async function upsertDealer(client, user, resellerId) {
  const existing = await client.query(
    'SELECT id FROM dealers WHERE user_id = $1 OR LOWER(email) = LOWER($2) LIMIT 1',
    [user.id, user.email]
  );
  if (existing.rows.length > 0) {
    await client.query(
      `UPDATE dealers
       SET user_id = $2, reseller_id = $3, name = $4, email = $5, phone = $6,
           address = $7, business_name = $8, shop_name = $8, trade_license = $9, status = 'active', updated_at = NOW()
       WHERE id = $1`,
      [existing.rows[0].id, user.id, resellerId, 'Demo Dealer', user.email, '+8801700000002', 'Demo Dealer Address', 'Demo Dealer Shop', 'DEMO-TRADE-001']
    );
    return;
  }

  await client.query(
    `INSERT INTO dealers (user_id, reseller_id, name, email, phone, address, business_name, shop_name, trade_license, status, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, 'active', NOW(), NOW())`,
    [user.id, resellerId, 'Demo Dealer', user.email, '+8801700000002', 'Demo Dealer Address', 'Demo Dealer Shop', 'DEMO-TRADE-001']
  );
}

async function main() {
  await ensureDealerUserIdColumn();

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    const reseller = await upsertUser(client, {
      email: 'reseller@emi-locker.com',
      role: 'reseller',
      name: 'Demo Reseller',
      phone: '+8801700000001'
    });
    await upsertReseller(client, reseller);

    const dealer = await upsertUser(client, {
      email: 'dealer@emi-locker.com',
      role: 'dealer',
      name: 'Demo Dealer',
      phone: '+8801700000002'
    });
    await upsertDealer(client, dealer, reseller.id);

    await client.query('COMMIT');

    console.log('Demo credentials created/updated:');
    console.log(`Reseller: reseller@emi-locker.com / ${PASSWORD}`);
    console.log(`Dealer:   dealer@emi-locker.com / ${PASSWORD}`);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await db.pool.end();
  }
}

main().catch((error) => {
  console.error('Failed to seed demo users:', error.message);
  process.exit(1);
});
