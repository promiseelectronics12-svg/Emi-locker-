const keyRoutes = require('./keys/keyRoutes');
const { initKeyCronJobs } = require('./keys/keyScheduler');
const { fraudRoutes, initFraudCronJobs } = require('./fraud');

module.exports = {
  keyRoutes,
  initKeyCronJobs,
  fraudRoutes,
  initFraudCronJobs
};