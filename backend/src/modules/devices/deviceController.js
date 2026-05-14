const asyncHandler = require('express-async-handler');
const { body, param, validationResult } = require('express-validator');
const deviceService = require('./deviceService');
const hardwareBindingService = require('./hardwareBindingService');
const logger = require('../../utils/logger');
const db = require('../../config/database');

const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ errors: errors.array() });
  }
  next();
};

const imeiValidation = body('imei')
  .matches(/^\d{15}$/)
  .withMessage('IMEI must be exactly 15 digits');

const serialValidation = body('serialNumber')
  .isString()
  .isLength({ min: 1, max: 64 })
  .withMessage('Serial number is required and must be 1-64 characters');

const socIdValidation = body('socId')
  .isString()
  .isLength({ min: 1, max: 128 })
  .withMessage('SoC ID is required and must be 1-128 characters');

const enrollmentTokenValidation = body('enrollmentToken')
  .isString()
  .isLength({ min: 1 })
  .withMessage('Enrollment token is required');

const deviceIdParam = param('id').isUUID().withMessage('Valid device ID is required');

const fcmTokenValidation = body('fcmToken')
  .isString()
  .isLength({ min: 1, max: 1024 })
  .withMessage('Valid FCM token is required');

const reasonValidation = body('reason')
  .optional()
  .isString()
  .isLength({ max: 500 })
  .withMessage('Reason must be a string with max 500 characters');

const unlockCodeValidation = body('unlockCode')
  .optional()
  .isString()
  .isLength({ min: 4, max: 8 })
  .withMessage('Unlock code must be 4-8 characters');

const enrollDevice = asyncHandler(async (req, res) => {
  const { enrollmentToken, imei, serialNumber, socId, dealerId, deviceName, model, brand } =
    req.body;

  const userId = req.user?.id;

  if (!enrollmentToken) {
    return res.status(400).json({ error: 'Enrollment token is required' });
  }

  if (!imei || !/^\d{15}$/.test(imei)) {
    return res.status(400).json({ error: 'Valid 15-digit IMEI is required' });
  }

  if (!serialNumber) {
    return res.status(400).json({ error: 'Serial number is required' });
  }

  if (!socId) {
    return res.status(400).json({ error: 'SoC ID is required' });
  }

  if (!dealerId) {
    return res.status(400).json({ error: 'Dealer ID is required' });
  }

  try {
    const result = await deviceService.enrollDevice({
      enrollmentToken,
      imei,
      serialNumber,
      socId,
      dealerId,
      userId,
      deviceName: deviceName || `${brand || ''} ${model || 'Unknown'}`.trim(),
      model,
      brand
    });

    logger.info(`Device enrolled via API: ${result.deviceId}`, {
      imei,
      dealerId,
      userId
    });

    res.status(201).json({
      success: true,
      message: 'Device enrolled successfully',
      data: result
    });
  } catch (error) {
    logger.error('Device enrollment failed:', error);

    if (error.message.includes('Invalid or expired enrollment token')) {
      return res.status(401).json({ error: error.message });
    }

    if (error.message.includes('already enrolled')) {
      return res.status(409).json({ error: error.message });
    }

    res.status(500).json({ error: 'Device enrollment failed' });
  }
});

const getDevice = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { verifyHardware } = req.query;

  const shouldVerifyHardware = verifyHardware === 'true';

  if (shouldVerifyHardware) {
    const { imei, serialNumber, socId } = req.query;

    if (!imei || !serialNumber || !socId) {
      return res.status(400).json({
        error: 'Hardware verification requires IMEI, serialNumber, and socId query parameters'
      });
    }

    try {
      await deviceService.verifyHardwareAndGetDevice(id, imei, serialNumber, socId);
    } catch (error) {
      if (error.message.includes('Hardware binding verification failed')) {
        return res.status(403).json({ error: 'Hardware binding verification failed' });
      }
      if (error.message.includes('Device has not been hardware bound')) {
        return res.status(400).json({ error: error.message });
      }
      throw error;
    }
  }

  try {
    const device = await deviceService.getDeviceInfo(id, !shouldVerifyHardware);

    res.json({
      success: true,
      data: device
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    logger.error('Failed to get device:', error);
    res.status(500).json({ error: 'Failed to retrieve device information' });
  }
});

const applyPolicy = asyncHandler(async (req, res) => {
  const { id } = req.params;

  try {
    const result = await deviceService.applyDeviceOwnerPolicies(id);

    logger.info(`Device Owner policies applied: ${id}`);

    res.json({
      success: true,
      message: 'Device Owner policies applied successfully',
      data: result
    });
  } catch (error) {
    logger.error('Failed to apply Device Owner policies:', error);

    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    res.status(500).json({ error: 'Failed to apply Device Owner policies' });
  }
});

const updateFcmToken = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { fcmToken } = req.body;

  if (!fcmToken) {
    return res.status(400).json({ error: 'FCM token is required' });
  }

  try {
    const result = await deviceService.updateFcmToken(id, fcmToken);

    logger.info(`FCM token updated for device: ${id}`);

    res.json({
      success: true,
      message: 'FCM token updated successfully',
      data: result
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (error.message.includes('Valid FCM token')) {
      return res.status(400).json({ error: error.message });
    }

    logger.error('Failed to update FCM token:', error);
    res.status(500).json({ error: 'Failed to update FCM token' });
  }
});

const getDeviceStatus = asyncHandler(async (req, res) => {
  const { id } = req.params;

  try {
    const status = await deviceService.getDeviceStatus(id);

    res.json({
      success: true,
      data: status
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    logger.error('Failed to get device status:', error);
    res.status(500).json({ error: 'Failed to retrieve device status' });
  }
});

const lockDevice = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { reason, unlockCode } = req.body;
  const lockedBy = req.user?.id || 'system';

  try {
    const result = await deviceService.lockDevice(id, reason, lockedBy, unlockCode);

    logger.info(`Device locked via API: ${id}`, { reason, lockedBy });

    res.json({
      success: true,
      message: 'Device locked successfully',
      data: result
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: error.message });
    }
    logger.error('Failed to lock device:', error);
    res.status(500).json({ error: 'Failed to lock device' });
  }
});

const unlockDevice = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { reason, unlockCode } = req.body;
  const unlockedBy = req.user?.id || 'system';

  try {
    const result = await deviceService.unlockDevice(id, reason, unlockedBy, unlockCode);

    logger.info(`Device unlocked via API: ${id}`, { reason, unlockedBy });

    res.json({
      success: true,
      message: 'Device unlocked successfully',
      data: result
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: error.message });
    }

    if (error.message === 'Invalid unlock code') {
      return res.status(403).json({ error: error.message });
    }

    logger.error('Failed to unlock device:', error);
    res.status(500).json({ error: 'Failed to unlock device' });
  }
});

const decoupleDevice = asyncHandler(async (req, res) => {
  const { id } = req.params;

  try {
    const result = await deviceService.decoupleDevice(id);

    logger.info(`Device decoupled via API: ${id}`);

    res.json({
      success: true,
      message: 'Device decoupled successfully',
      data: result
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    logger.error('Failed to decouple device:', error);
    res.status(500).json({ error: 'Failed to decouple device' });
  }
});

const getDevicesByOwner = asyncHandler(async (req, res) => {
  const userId = req.user?.id;

  if (!userId) {
    return res.status(401).json({ error: 'User not authenticated' });
  }

  try {
    const result = await db.query(
      `SELECT d.id, d.amapi_device_id, d.imei, d.device_name, d.model, d.brand,
              d.status, d.enrolled_at, d.policy_last_applied,
              dl.name as dealer_name
       FROM devices d
       LEFT JOIN dealers dl ON d.dealer_id = dl.id
       WHERE d.owner_id = $1
       ORDER BY d.enrolled_at DESC`,
      [userId]
    );

    res.json({
      success: true,
      data: result.rows
    });
  } catch (error) {
    logger.error('Failed to get user devices:', error);
    res.status(500).json({ error: 'Failed to retrieve devices' });
  }
});

const verifyHardwareBinding = asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { imei, serialNumber, socId } = req.body;

  if (!imei || !serialNumber || !socId) {
    return res.status(400).json({
      error: 'IMEI, serialNumber, and socId are required for verification'
    });
  }

  try {
    const verification = await hardwareBindingService.verifyDeviceHardware(
      id,
      imei,
      serialNumber,
      socId
    );

    res.json({
      success: true,
      data: verification
    });
  } catch (error) {
    if (error.message === 'Device not found') {
      return res.status(404).json({ error: 'Device not found' });
    }

    if (error.message.includes('Hardware binding verification failed')) {
      return res.status(403).json({
        success: false,
        error: 'Hardware binding verification failed',
        data: { isValid: false }
      });
    }

    logger.error('Hardware verification error:', error);
    res.status(500).json({ error: 'Hardware verification failed' });
  }
});

module.exports = {
  enrollDevice,
  getDevice,
  applyPolicy,
  updateFcmToken,
  getDeviceStatus,
  lockDevice,
  unlockDevice,
  decoupleDevice,
  getDevicesByOwner,
  verifyHardwareBinding,
  validateRequest,
  imeiValidation,
  serialValidation,
  socIdValidation,
  enrollmentTokenValidation,
  deviceIdParam,
  fcmTokenValidation,
  reasonValidation,
  unlockCodeValidation
};
