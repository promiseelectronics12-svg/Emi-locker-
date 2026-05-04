const express = require('express');
const router = express.Router();
const deviceController = require('../controllers/deviceController');
const { authenticateToken } = require('../middleware/auth');
const { validateSignedDeviceCommand } = require('../middleware/deviceAuth');
const { body } = require('express-validator');
const { validateRequest } = require('../middleware/validateRequest');

router.post('/register',
  authenticateToken,
  body('imei').matches(/^\d{15}$/).withMessage('IMEI must be 15 digits'),
  body('enrollment_token').notEmpty(),
  body('dealer_id').isUUID(),
  validateRequest,
  deviceController.registerDevice
);

router.get('/my', authenticateToken, deviceController.getMyDevices);

router.get('/:id',
  authenticateToken,
  deviceController.validateDeviceOwnership,
  deviceController.getDevice
);

router.patch('/:id/status',
  authenticateToken,
  body('status').isIn(['active', 'locked', 'unlocked', 'stolen', 'disabled']),
  body('reason').optional().isString(),
  validateRequest,
  deviceController.updateDeviceStatus
);

router.post('/:id/lock',
  authenticateToken,
  validateSignedDeviceCommand,
  body('reason').optional().isString(),
  validateRequest,
  deviceController.validateDeviceOwnership,
  deviceController.lockDevice
);

router.post('/:id/unlock',
  authenticateToken,
  validateSignedDeviceCommand,
  body('reason').optional().isString(),
  validateRequest,
  deviceController.validateDeviceOwnership,
  deviceController.unlockDevice
);

module.exports = router;
