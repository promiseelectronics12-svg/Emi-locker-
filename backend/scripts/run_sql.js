const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function run() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });
  try {
    await client.connect();
    const filePath = process.argv[2] || 'd:\\EMI APP\\database\\migrations\\100_dealer_device_settings.sql';
    const sql = fs.readFileSync(filePath, 'utf-8');
    await client.query(sql);
    console.log(`Successfully applied ${filePath}`);
  } catch (err) {
    console.error('Error applying SQL:', err);
  } finally {
    await client.end();
  }
}

run();
