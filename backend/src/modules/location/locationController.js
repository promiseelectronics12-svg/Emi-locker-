const locationService = require('./locationService');
const logger = require('../../utils/logger');

class LocationController {
  async pullLocation(req, res) {
    try {
      const { deviceId } = req.params;
      const { reason } = req.body;
      const userId = req.user.id;

      const result = await locationService.pullLocationNow(deviceId, reason, userId);

      res.json({
        success: true,
        message: 'Location pull request sent',
        data: result
      });
    } catch (error) {
      logger.error('Pull location error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }

  async reportLocation(req, res) {
    try {
      const { deviceId } = req.params;
      const { latitude, longitude, accuracy, timestamp, battery_level, pull_id } = req.body;

      const result = await locationService.recordLocationReport(deviceId, {
        latitude,
        longitude,
        accuracy,
        timestamp,
        battery_level,
        pull_id
      });

      if (result.alert) {
        return res.json({
          success: true,
          message: 'Location recorded',
          alert: result.alert
        });
      }

      res.json({
        success: true,
        message: 'Location recorded',
        data: {
          locationId: result.locationId,
          geofenceTriggered: result.geofenceTriggered
        }
      });
    } catch (error) {
      logger.error('Report location error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }

  async getLocationHistory(req, res) {
    try {
      const { deviceId } = req.params;
      const limit = parseInt(req.query.limit, 10) || 10;

      const history = await locationService.getLocationHistory(deviceId, limit);

      res.json({
        success: true,
        data: history
      });
    } catch (error) {
      logger.error('Get location history error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }

  async setGeofence(req, res) {
    try {
      const { deviceId } = req.params;
      const { type, name, center_latitude, center_longitude, radius_meters, coordinates, enabled } =
        req.body;
      const userId = req.user.id;

      const result = await locationService.setGeofence(
        deviceId,
        {
          type,
          name,
          center_latitude,
          center_longitude,
          radius_meters,
          coordinates,
          enabled: enabled !== false
        },
        userId
      );

      res.json({
        success: true,
        message: 'Geofence set successfully',
        data: result
      });
    } catch (error) {
      logger.error('Set geofence error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }

  async getGeofence(req, res) {
    try {
      const { deviceId } = req.params;

      const geofence = await locationService.getGeofence(deviceId);

      res.json({
        success: true,
        data: geofence
      });
    } catch (error) {
      logger.error('Get geofence error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }

  async deleteGeofence(req, res) {
    try {
      const { deviceId } = req.params;
      const userId = req.user.id;

      await locationService.deleteGeofence(deviceId, userId);

      res.json({
        success: true,
        message: 'Geofence deleted successfully'
      });
    } catch (error) {
      logger.error('Delete geofence error:', error);
      res.status(400).json({
        success: false,
        error: error.message
      });
    }
  }
}

module.exports = new LocationController();
