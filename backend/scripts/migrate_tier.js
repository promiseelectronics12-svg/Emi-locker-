require('dotenv').config();
const { Client } = require('pg');

const client = new Client({
  connectionString: process.env.DATABASE_URL
});

async function run() {
  try {
    await client.connect();
    
    // Fetch current enrollments safely
    const res = await client.query('SELECT * FROM enrollments');
    console.log('\nCurrent Enrollments before cleanup:');
    console.table(res.rows);
    
    // Delete test device enrollment so it can be cleanly re-enrolled
    if (res.rows.length > 0) {
      console.log('\nClearing existing enrollments to allow clean re-enrollment...');
      await client.query('DELETE FROM enrollments');
      console.log('✅ Cleared test enrollments.');
    } else {
      console.log('\nNo existing enrollments found. Ready for new test enrollment.');
    }
    
  } catch (err) {
    console.error('❌ Error:', err);
  } finally {
    await client.end();
  }
}

run();
