const cron = require('node-cron');
const fraudService = require('./fraudService');
const logger = require('../../utils/logger');

let fraudDetectionTask = null;

function initFraudCronJobs() {
  logger.info('Initializing fraud detection cron jobs');

  fraudDetectionTask = cron.schedule('0 2 * * *', async () => {
    logger.info('Starting nightly fraud detection run');
    try {
      const results = await fraudService.runAllAnomalyDetections();
      logger.info('Nightly fraud detection completed', { results });
    } catch (error) {
      logger.error('Nightly fraud detection failed:', error);
    }
  }, {
    scheduled: true,
    timezone: 'Asia/Dhaka',
  });

  logger.info('Fraud detection cron job scheduled: runs daily at 2:00 AM Bangladesh time');
}

function stopFraudCronJobs() {
  if (fraudDetectionTask) {
    fraudDetectionTask.stop();
    logger.info('Fraud detection cron job stopped');
  }
}

async function runFraudDetectionNow() {
  logger.info('Manual fraud detection triggered');
  return fraudService.runAllAnomalyDetections();
}

module.exports = {
  initFraudCronJobs,
  stopFraudCronJobs,
  runFraudDetectionNow,
};