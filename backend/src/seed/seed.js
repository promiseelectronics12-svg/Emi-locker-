require('dotenv').config();
const { runMigrations } = require('../migrations/001_initial_schema');
const db = require('../config/database');
const logger = require('../config/logger');

const seedDatabase = async () => {
  try {
    logger.info('Starting database seeding...');

    const bcrypt = require('bcrypt');
    const adminPasswordHash = await bcrypt.hash('admin123', 12);
    const dealerPasswordHash = await bcrypt.hash('dealer123', 12);

    // Seed admin into users table (used by the auth module)
    await db.query(`
      INSERT INTO users (email, password_hash, name, phone, role, status, created_at, updated_at)
      VALUES ('admin@emi-locker.local', $1, 'Admin User', '+8801700000000', 'admin', 'active', NOW(), NOW())
      ON CONFLICT (email) DO NOTHING
    `, [adminPasswordHash]);

    await db.query(`
      INSERT INTO dealers (name, email, phone, password_hash, company_name, role)
      VALUES
        ('Admin User', 'admin@emi-locker.local', '+8801700000000', $1, 'EMI Locker HQ', 'admin'),
        ('Test Dealer', 'dealer@test.com', '+8801700000001', $2, 'Test Electronics', 'dealer')
      ON CONFLICT (email) DO NOTHING
    `, [adminPasswordHash, dealerPasswordHash]);

    await db.query(`
      INSERT INTO users (nid, name, email, phone, address)
      VALUES 
        ('1234567890', 'Test User', 'user@test.com', '+8801700000010', 'Dhaka, Bangladesh'),
        ('0987654321', 'John Doe', 'john@test.com', '+8801700000011', 'Chittagong, Bangladesh')
      ON CONFLICT (nid) DO NOTHING
    `);

    logger.info('Database seeding completed');
  } catch (error) {
    logger.error('Seeding failed', error);
    throw error;
  }
};

if (require.main === module) {
  (async () => {
    try {
      await runMigrations();
      await seedDatabase();
      process.exit(0);
    } catch (error) {
      logger.error('Seed script failed', error);
      process.exit(1);
    }
  })();
}

module.exports = { seedDatabase };