const express = require('express');

const router = express.Router();
const adminRoutes = require('../modules/admin/adminRoutes');

router.use('/auth', require('./auth'));
router.use('/devices', require('../modules/devices/deviceRoutes'));
router.use('/emi', require('../modules/emi/emiRoutes'));
router.use('/lock', require('../modules/lock/lockRoutes'));
router.use('/decoupling', require('../modules/decoupling/decouplingRoutes'));
router.use('/users', require('./users'));
router.use('/payments', require('./payments'));
router.use('/agreements', require('./agreements'));
router.use('/dealer', require('./dealer'));
router.use('/dealer/enrollments', require('../modules/enrollment/enrollmentRoutes'));
router.use('/reseller', require('./reseller'));
router.use('/dealers', require('./dealers'));

router.use('/admin', adminRoutes);
router.use('/admin/invites', require('./invites'));
router.use('/notifications', require('../modules/notifications/notification.routes'));
router.use('/alerts', require('./alerts'));
router.use('/keys', require('../modules/keys/keyRoutes'));
router.use('/device-activation', require('../modules/deviceActivation/deviceActivationRoutes'));
router.use('/device', require('../modules/deviceActivation/deviceRuntimeRoutes'));
router.use('/location', require('../modules/location/locationRoutes'));
router.use('/fraud', require('../modules/fraud/fraudRoutes'));
router.use('/risk', require('../modules/risk/riskRoutes'));
router.use('/evidence', require('./evidence'));
router.use('/credit', require('../modules/credit/creditRoutes'));
router.use('/events', require('../modules/sse/sseRoutes'));

module.exports = router;
