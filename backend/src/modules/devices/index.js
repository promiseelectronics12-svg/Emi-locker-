const deviceRoutes = require('./deviceRoutes');
const deviceController = require('./deviceController');
const deviceService = require('./deviceService');
const amapiService = require('./amapiService');
const firebaseService = require('./firebaseService');
const hardwareBindingService = require('./hardwareBindingService');

module.exports = {
  deviceRoutes,
  deviceController,
  deviceService,
  amapiService,
  firebaseService,
  hardwareBindingService
};
