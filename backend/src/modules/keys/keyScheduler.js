const cron = require('node-cron');
const db = require('../../config/database');
const logger = require('../../utils/logger');

async function checkDealerVelocity() {
  try {
    const result = await db.query(
      `SELECT dealer_id, COUNT(*) as count
       FROM activation_keys
       WHERE status = 'activated'
         AND activated_at > NOW() - INTERVAL '24 hours'
         AND dealer_id IS NOT NULL
       GROUP BY dealer_id
       HAVING COUNT(*) >= 10`
    );

    for (const row of result.rows) {
      await db.query(
        `INSERT INTO audit_logs (user_id, action, metadata, created_at)
         VALUES ($1, 'VELOCITY_ALERT', $2, NOW())`,
        [row.dealer_id, JSON.stringify({ dealerId: row.dealer_id, keysUsed24h: parseInt(row.count, 10), threshold: 10 })]
      );
      logger.warn(`Velocity alert: Dealer ${row.dealer_id} activated ${row.count} keys in 24 hours`);
    }
  } catch (error) {
    logger.error('Velocity check cron error:', error);
  }
}

function initKeyCronJobs() {
  cron.schedule('0 0 * * *', checkDealerVelocity);
  logger.info('Key velocity cron job initialized');
}

module.exports = {
  initKeyCronJobs,
  checkDealerVelocity
};
