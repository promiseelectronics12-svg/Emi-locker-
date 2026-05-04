const decouplingRoutes = require('./decouplingRoutes');
const decouplingController = require('./decouplingController');
const decouplingService = require('./decouplingService');
const decouplingModel = require('./decouplingModel');
const decouplingScheduler = require('./decouplingScheduler');
const { DECOUPLING_STATES, VALID_TRANSITIONS } = require('./decouplingModel');

function initDecouplingModule() {
  decouplingService.initialize();
  decouplingScheduler.startCronFallback(
    decouplingService.handleFraudWindowExpired.bind(decouplingService),
    decouplingService.handleAdminNotifyTimeout.bind(decouplingService)
  );
}

module.exports = {
  decouplingRoutes,
  decouplingController,
  decouplingService,
  decouplingModel,
  decouplingScheduler,
  DECOUPLING_STATES,
  VALID_TRANSITIONS,
  initDecouplingModule,
  close: decouplingScheduler.close,
};
