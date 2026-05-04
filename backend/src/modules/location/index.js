const locationRoutes = require('./locationRoutes');
const locationService = require('./locationService');
const locationScheduler = require('./locationScheduler');
const logger = require('../../utils/logger');

async function initLocationModule() {
  try {
    await locationService.initAutoLocationWorker();
    locationScheduler.start();
    logger.info('Location module initialized');
  } catch (error) {
    logger.error('Failed to initialize location module:', error);
  }
}

module.exports = {
  locationRoutes,
  locationService,
  locationScheduler,
  initLocationModule
};