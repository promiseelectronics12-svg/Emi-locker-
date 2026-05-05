require('dotenv').config();
const { Pool } = require('pg');
const crypto = require('crypto');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function seedDemoDevices() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // 1. Get or create the demo dealer
    let dealerResult = await client.query(`SELECT id FROM dealers WHERE email = 'dealer@test.com' LIMIT 1`);
    let dealerId;
    
    if (dealerResult.rowCount === 0) {
      console.log('Dealer not found. Creating demo dealer...');
      const dealerRes = await client.query(`
        INSERT INTO dealers (name, email, phone, address, status)
        VALUES ('Test Dealer', 'dealer@test.com', '+8801700000001', 'Test Electronics HQ', 'active')
        RETURNING id
      `);
      dealerId = dealerRes.rows[0].id;
    } else {
      dealerId = dealerResult.rows[0].id;
    }

    // 2. Create Demo Devices
    const devices = [
      {
        imei: '868120045612345',
        device_name: 'Samsung Galaxy A14',
        model: 'SM-A145F',
        brand: 'Samsung',
        lat: 23.8103, // Dhaka
        lng: 90.4125
      },
      {
        imei: '868120045612346',
        device_name: 'Xiaomi Redmi Note 12',
        model: '23028RN4DG',
        brand: 'Xiaomi',
        lat: 22.3569, // Chittagong
        lng: 91.7832
      },
      {
        imei: '868120045612347',
        device_name: 'Vivo Y16',
        model: 'V2204',
        brand: 'Vivo',
        lat: 24.8949, // Sylhet
        lng: 91.8687
      }
    ];

    for (const dev of devices) {
      // Insert Device
      const devRes = await client.query(`
        INSERT INTO devices (
          imei, device_name, model, brand, dealer_id, status, lock_level
        ) VALUES (
          $1, $2, $3, $4, $5, 'active', 'NONE'
        ) RETURNING id
      `, [dev.imei, dev.device_name, dev.model, dev.brand, dealerId]);
      
      const deviceId = devRes.rows[0].id;

      // Insert recent location history (last 5 hours)
      for (let i = 4; i >= 0; i--) {
        // Add some random jitter to make the path look realistic
        const jitterLat = (Math.random() - 0.5) * 0.005;
        const jitterLng = (Math.random() - 0.5) * 0.005;
        
        await client.query(`
          INSERT INTO location_reports (
            device_id, latitude, longitude, accuracy, timestamp, battery_level
          ) VALUES (
            $1, $2, $3, $4, NOW() - INTERVAL '${i} hours', $5
          )
        `, [
          deviceId, 
          dev.lat + jitterLat, 
          dev.lng + jitterLng, 
          Math.floor(Math.random() * 20) + 5, // Accuracy 5-25m
          Math.floor(Math.random() * 30) + 70 // Battery 70-100%
        ]);
      }

      // Insert an EMI Schedule so it shows up fully
      await client.query(`
        INSERT INTO emi_schedules (
          device_id, total_amount, down_payment, emi_amount, duration, start_date, status
        ) VALUES (
          $1, 25000, 5000, 2000, 10, CURRENT_DATE, 'active'
        )
      `, [deviceId]);
    }

    await client.query('COMMIT');
    console.log('Successfully seeded 3 demo devices with location history!');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Failed to seed demo devices:', error);
  } finally {
    client.release();
    await pool.end();
  }
}

seedDemoDevices();
