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
router.use('/dealer', require('./dealer'));
router.use('/reseller', require('./reseller'));
router.use('/dealers', require('./dealers'));
router.use('/admin', adminRoutes);
router.use('/notifications', require('../modules/notifications/notification.routes'));
router.use('/keys', require('../modules/keys/keyRoutes'));
router.use('/location', require('../modules/location/locationRoutes'));
router.use('/fraud', require('../modules/fraud/fraudRoutes'));

module.exports = router;
