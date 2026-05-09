require('dotenv').config();
const Redis = require('ioredis');

const url = process.env.UPSTASH_REDIS_URL;

if (!url) {
  console.error('❌ ERROR: UPSTASH_REDIS_URL is empty in your .env file!');
  console.log('Please paste your Upstash URL (starting with rediss://) into the .env file and save it.');
  process.exit(1);
}

console.log('Attempting to connect to Upstash...');

const client = new Redis(url, {
  tls: { rejectUnauthorized: false },
  connectTimeout: 5000,
  maxRetriesPerRequest: 1
});

client.on('error', (err) => {
  console.error('❌ CONNECTION FAILED:');
  console.error(err.message);
  process.exit(1);
});

client.on('connect', async () => {
  console.log('✅ Connected to Upstash successfully!');
  
  try {
    const pingResult = await client.ping();
    console.log(`✅ PING result: ${pingResult}`);
    
    await client.set('test_key', 'Hello from EMI Locker!');
    const value = await client.get('test_key');
    console.log(`✅ Read test value: ${value}`);
    
    await client.del('test_key');
    
    console.log('🎉 Smoke test passed. Your Upstash URL is fully ready for production!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Test operations failed:', err.message);
    process.exit(1);
  }
});
