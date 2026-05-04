const cron = require('node-cron');
const db = require('../../config/database');
const logger = require('../../utils/logger');

async function expireUnusedKeys() {
  try {
    const result = await db.query(
      `UPDATE keys
       SET status = 'EXPIRED', expired_at = NOW()
       WHERE status IN ('GENERATED', 'ASSIGNED')
       AND expires_at < NOW()
       RETURNING id, key_string, reseller_id, dealer_id`
    );

    if (result.rows.length > 0) {
      logger.info(`Expired ${result.rows.length} unused keys`);
      await db.query(
        `INSERT INTO audit_logs (user_id, action, metadata, created_at)
         VALUES (NULL, 'KEYS_EXPIRED_CRON', $1, NOW())`,
        [JSON.stringify({ count: result.rows.length, keyIds: result.rows.map(r => r.id) })]
      );
    }
  } catch (error) {
    logger.error('Expire keys cron error:', error);
  }
}

async function checkDealerVelocity() {
  try {
    const result = await db.query(
      `SELECT dealer_id, COUNT(*) as count
       FROM keys
       WHERE consumed_at > NOW() - INTERVAL '24 hours'
       GROUP BY dealer_id
       HAVING COUNT(*) >= 10`
    );

    for (const row of result.rows) {
      await db.query(
        `INSERT INTO audit_logs (user_id, action, metadata, created_at)
         VALUES ($1, 'VELOCITY_ALERT', $2, NOW())`,
        [row.dealer_id, JSON.stringify({ dealerId: row.dealer_id, keysUsed24h: parseInt(row.count), threshold: 10 })]
      );
      logger.warn(`Velocity alert: Dealer ${row.dealer_id} used ${row.count} keys in 24 hours`);
    }
  } catch (error) {
    logger.error('Velocity check cron error:', error);
  }
}

function initKeyCronJobs() {
  cron.schedule('0 * * * *', async () => {
    await expireUnusedKeys();
  });

  cron.schedule('0 0 * * *', async () => {
    await checkDealerVelocity();
  });

  logger.info('Key cron jobs initialized');
}

module.exports = {
  initKeyCronJobs,
  expireUnusedKeys,
  checkDealerVelocity
};