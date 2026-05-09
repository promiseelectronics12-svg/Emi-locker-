const db = require('../../config/database');
const logger = require('../../utils/logger');
const fcmService = require('../notifications/fcm.service');
const deviceService = require('../devices/deviceService');
const kmsSigningService = require('../devices/kmsSigningService');
const Queue = require('bull');
const crypto = require('crypto');

const REDIS_URL = process.env.BULL_REDIS_URL || process.env.UPSTASH_REDIS_URL || process.env.REDIS_URL || 'redis://localhost:6379';
const AUTO_LOCK_LEVEL = 7;

class LocationService {
  getLocationPullQueue() {
    if (!this._locationPullQueue) {
      this._locationPullQueue = new Queue('location-pull', REDIS_URL, {
        defaultJobOptions: {
          attempts: 3,
          backoff: { type: 'exponential', delay: 2000 },
          removeOnComplete: true,
          removeOnFail: false
        }
      });

      this._locationPullQueue.on('failed', (job, err) => {
        logger.error(`Location pull job ${job.id} failed:`, err.message);
      });

      this._locationPullQueue.on('completed', (job) => {
        logger.info(`Location pull job ${job.id} completed for device ${job.data.deviceId}`);
      });
    }
    return this._locationPullQueue;
  }

  getAutoLocationQueue() {
    if (!this._autoLocationQueue) {
      this._autoLocationQueue = new Queue('auto-location', REDIS_URL, {
        defaultJobOptions: {
          attempts: 3,
          backoff: { type: 'exponential', delay: 2000 },
          removeOnComplete: true,
          removeOnFail: false
        }
      });

      this._autoLocationQueue.on('failed', (job, err) => {
        logger.error(`Auto-location job ${job.id} failed:`, err.message);
      });
    }
    return this._autoLocationQueue;
  }

  async pullLocationNow(deviceId, reason, userId) {
    const device = await deviceService.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    const pullId = `pull_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const nonce = crypto.randomBytes(16).toString('hex');
    const timestamp = new Date().toISOString();
    const expiresAt = new Date(Date.now() + 60000).toISOString();

    let fcmDelivered = false;

    if (device.fcm_token) {
      const commandPayload = {
        deviceId,
        pullId,
        command: 'GET_LOCATION',
        reason,
        timestamp,
        nonce,
        serverId: process.env.SERVER_ID || 'server-001',
        expiresAt,
        imei: device.imei
      };

      try {
        const signatureResult = await kmsSigningService.sign(commandPayload);
        const payload = {
          type: 'PULL_LOCATION',
          command: 'GET_LOCATION',
          pullId,
          reason,
          requestedBy: userId,
          timestamp,
          nonce,
          serverId: process.env.SERVER_ID || 'server-001',
          expiresAt,
          imei: device.imei,
          hmacSignature: signatureResult.signature,
          signatureProvider: signatureResult.provider,
          signatureKeyId: signatureResult.keyId
        };
        const result = await fcmService.sendToDevice(device.fcm_token, payload);
        fcmDelivered = result.success;
      } catch (err) {
        logger.warn(`FCM delivery failed for location pull on device ${deviceId}: ${err.message}`);
      }
    } else {
      logger.warn(`Device ${deviceId} has no FCM token — location pull queued without push delivery`);
    }

    await db.query(
      `INSERT INTO location_pull_requests (device_id, pull_id, reason, requested_by, status, requested_at, expires_at)
       VALUES ($1, $2, $3, $4, 'pending', NOW(), $5)`,
      [deviceId, pullId, reason, userId, expiresAt]
    );

    logger.info(`Location pull requested for device ${deviceId}`, { pullId, reason });

    await this.logAuditEvent({
      actor: userId,
      action: 'PULL_LOCATION',
      deviceId,
      metadata: { pullId, reason, nonce }
    });

    return {
      pullId,
      deviceId,
      status: 'pending',
      expiresAt,
      fcm_delivered: fcmDelivered,
      message: fcmDelivered
        ? 'Location pull sent — device should respond within 60 seconds'
        : 'Pull request queued — device will report location on next check-in'
    };
  }

  async recordLocationReport(deviceId, locationData) {
    const { latitude, longitude, accuracy, timestamp, battery_level } = locationData;

    // Validate coordinate bounds
    const lat = parseFloat(latitude);
    const lon = parseFloat(longitude);
    if (isNaN(lat) || lat < -90 || lat > 90) {
      throw new Error('Invalid latitude: must be a number between -90 and 90');
    }
    if (isNaN(lon) || lon < -180 || lon > 180) {
      throw new Error('Invalid longitude: must be a number between -180 and 180');
    }

    const device = await deviceService.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    // Rate-limit: max 1 location submission per 30 seconds per device
    const lastEntry = await db.query(
      `SELECT created_at FROM location_reports WHERE device_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [deviceId]
    );
    if (lastEntry.rows.length > 0) {
      const secondsSinceLast = (Date.now() - new Date(lastEntry.rows[0].created_at).getTime()) / 1000;
      if (secondsSinceLast < 30) {
        throw new Error('Location update rate limit exceeded (max 1 per 30 seconds)');
      }
    }

    const pendingPull = await db.query(
      `SELECT id, pull_id FROM location_pull_requests
       WHERE device_id = $1 AND status = 'pending' AND expires_at > NOW()
       ORDER BY requested_at DESC LIMIT 1`,
      [deviceId]
    );

    // Wrap all writes in a transaction for atomicity
    await db.query('BEGIN');
    let locationId;
    try {
      if (pendingPull.rows.length > 0) {
        await db.query(
          `UPDATE location_pull_requests SET status = 'completed', responded_at = NOW() WHERE id = $1`,
          [pendingPull.rows[0].id]
        );
      }

      const result = await db.query(
        `INSERT INTO location_reports (device_id, latitude, longitude, accuracy, timestamp, battery_level, pull_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [deviceId, lat, lon, accuracy, timestamp, battery_level || null, pendingPull.rows[0]?.pull_id || null]
      );
      locationId = result.rows[0].id;

      await db.query(
        `UPDATE devices SET last_location_lat = $1, last_location_lng = $2, last_location_time = $3,
         battery_level = $4, updated_at = NOW() WHERE id = $5`,
        [lat, lon, timestamp, battery_level || null, deviceId]
      );
      await db.query('COMMIT');
    } catch (err) {
      await db.query('ROLLBACK');
      throw err;
    }

    // Prune old location history (keep last 10)
    const historyCount = await db.query(
      `SELECT COUNT(*) FROM location_reports WHERE device_id = $1`,
      [deviceId]
    );
    if (parseInt(historyCount.rows[0].count) > 10) {
      await db.query(
        `DELETE FROM location_reports WHERE id IN (
           SELECT id FROM location_reports WHERE device_id = $1
           ORDER BY timestamp ASC LIMIT $2
         )`,
        [deviceId, parseInt(historyCount.rows[0].count) - 10]
      );
    }

    logger.info(`Location recorded for device ${deviceId}`, { latitude: lat, longitude: lon });

    let alert = null;
    let geofenceTriggered = false;

    const geofence = await this.getActiveGeofence(deviceId);
    if (geofence) {
      const outsideGeofence = await this.checkGeofenceViolation(lat, lon, geofence);
      if (outsideGeofence) {
        geofenceTriggered = true;
        alert = await this.createGeofenceAlert(deviceId, geofence, lat, lon);
      }
    }

    return {
      locationId,
      geofenceTriggered,
      alert
    };
  }

  async getLocationHistory(deviceId, limit = 10) {
    const result = await db.query(
      `SELECT lr.id, lr.latitude, lr.longitude, lr.accuracy, lr.timestamp, lr.battery_level, lr.pull_id,
              lpr.reason as pull_reason, lpr.requested_by
       FROM location_reports lr
       LEFT JOIN location_pull_requests lpr ON lr.pull_id = lpr.pull_id
       WHERE lr.device_id = $1
       ORDER BY lr.timestamp DESC
       LIMIT $2`,
      [deviceId, limit]
    );

    return result.rows.map(row => ({
      id: row.id,
      latitude: row.latitude,
      longitude: row.longitude,
      accuracy: row.accuracy,
      timestamp: row.timestamp,
      batteryLevel: row.battery_level,
      pullId: row.pull_id,
      pullReason: row.pull_reason,
      requestedBy: row.requested_by
    }));
  }

  async setGeofence(deviceId, geofenceData, userId) {
    const device = await deviceService.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    if (geofenceData.type === 'circle') {
      if (geofenceData.center_latitude === undefined || geofenceData.center_longitude === undefined || !geofenceData.radius_meters) {
        throw new Error('Circle geofence requires center_latitude, center_longitude, and radius_meters');
      }
    } else if (geofenceData.type === 'polygon') {
      if (!geofenceData.coordinates || geofenceData.coordinates.length < 3) {
        throw new Error('Polygon geofence requires at least 3 coordinates');
      }
    }

    await db.query(
      `DELETE FROM geofences WHERE device_id = $1`,
      [deviceId]
    );

    const coordinatesJson = geofenceData.type === 'polygon'
      ? JSON.stringify(geofenceData.coordinates)
      : null;

    const result = await db.query(
      `INSERT INTO geofences (device_id, name, type, center_latitude, center_longitude, radius_meters, coordinates, enabled, created_by, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
       RETURNING *`,
      [
        deviceId,
        geofenceData.name,
        geofenceData.type,
        geofenceData.center_latitude || null,
        geofenceData.center_longitude || null,
        geofenceData.radius_meters || null,
        coordinatesJson,
        geofenceData.enabled,
        userId
      ]
    );

    logger.info(`Geofence set for device ${deviceId}`, { name: geofenceData.name, type: geofenceData.type });

    await this.logAuditEvent({
      actor: userId,
      action: 'SET_GEOFENCE',
      deviceId,
      metadata: { name: geofenceData.name, type: geofenceData.type }
    });

    return this.formatGeofence(result.rows[0]);
  }

  async getGeofence(deviceId) {
    const result = await db.query(
      `SELECT g.*, u.name as created_by_name
       FROM geofences g
       LEFT JOIN users u ON g.created_by = u.id
       WHERE g.device_id = $1
       ORDER BY g.created_at DESC
       LIMIT 1`,
      [deviceId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.formatGeofence(result.rows[0]);
  }

  async getActiveGeofence(deviceId) {
    const result = await db.query(
      `SELECT * FROM geofences WHERE device_id = $1 AND enabled = true`,
      [deviceId]
    );

    return result.rows.length > 0 ? result.rows[0] : null;
  }

  async deleteGeofence(deviceId, userId) {
    await db.query(`DELETE FROM geofences WHERE device_id = $1`, [deviceId]);
    logger.info(`Geofence deleted for device ${deviceId}`);

    await this.logAuditEvent({
      actor: userId || 'system',
      action: 'DELETE_GEOFENCE',
      deviceId,
      metadata: {}
    });
  }

  async checkGeofenceViolation(latitude, longitude, geofence) {
    if (geofence.type === 'circle') {
      const distance = this.haversineDistance(
        latitude, longitude,
        geofence.center_latitude, geofence.center_longitude
      );
      return distance > geofence.radius_meters;
    } else if (geofence.type === 'polygon') {
      return !this.pointInPolygon(latitude, longitude, geofence.coordinates);
    }
    return false;
  }

  haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = this.toRad(lat2 - lat1);
    const dLon = this.toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(this.toRad(lat1)) * Math.cos(this.toRad(lat2)) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  toRad(deg) {
    return deg * (Math.PI / 180);
  }

  pointInPolygon(lat, lng, coordinates) {
    let inside = false;
    const n = coordinates.length;

    for (let i = 0, j = n - 1; i < n; j = i++) {
      const xi = coordinates[i].longitude;
      const yi = coordinates[i].latitude;
      const xj = coordinates[j].longitude;
      const yj = coordinates[j].latitude;

      const intersect = ((yi > lat) !== (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }

    return inside;
  }

  async createGeofenceAlert(deviceId, geofence, latitude, longitude) {
    const device = await deviceService.getDeviceById(deviceId);
    if (!device) return null;

    if (device.status !== 'locked') {
      logger.info(`Device ${deviceId} outside geofence but not locked — no alert`);
      return null;
    }

    const alertId = `gf_alert_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    await db.query(
      `INSERT INTO geofence_alerts (device_id, geofence_id, alert_id, latitude, longitude, triggered_at, acknowledged)
       VALUES ($1, $2, $3, $4, $5, NOW(), false)`,
      [deviceId, geofence.id, alertId, latitude, longitude]
    );

    const payload = {
      type: 'GEOFENCE_ALERT',
      alertId,
      deviceId,
      geofenceName: geofence.name,
      latitude,
      longitude,
      timestamp: new Date().toISOString(),
      message: `Device has left ${geofence.name} boundary while locked`
    };

    if (device.dealer_id) {
      const dealerResult = await db.query(
        `SELECT u.fcm_token FROM users u WHERE u.dealer_id = $1 AND u.role = 'dealer' LIMIT 1`,
        [device.dealer_id]
      );

      if (dealerResult.rows.length > 0 && dealerResult.rows[0].fcm_token) {
        await fcmService.sendToDevice(dealerResult.rows[0].fcm_token, payload);
      }
    }

    await db.query(
      `INSERT INTO alerts (dealer_id, device_id, alert_type, title, message, metadata, status, created_at)
       VALUES ($1, $2, 'GEOFENCE_VIOLATION', $3, $4, $5, 'active', NOW())`,
      [
        device.dealer_id,
        deviceId,
        'Geofence Alert',
        payload.message,
        JSON.stringify({ alertId, latitude, longitude, geofenceName: geofence.name })
      ]
    );

    logger.warn(`Geofence alert created for device ${deviceId}`, { alertId, geofence: geofence.name });

    await this.logAuditEvent({
      actor: 'system',
      action: 'GEOFENCE_ALERT',
      deviceId,
      metadata: { alertId, latitude, longitude, geofenceName: geofence.name }
    });

    return {
      alertId,
      type: 'GEOFENCE_VIOLATION',
      message: payload.message,
      latitude,
      longitude,
      geofenceName: geofence.name
    };
  }

  async scheduleAutoLocation(deviceId) {
    const queue = this.getAutoLocationQueue();

    const existingJob = await queue.getRepeatableJobs();
    const existingForDevice = existingJob.find(j => j.name === `auto-location-${deviceId}`);
    if (existingForDevice) {
      await queue.removeRepeatableByKey(existingForDevice.key);
    }

    const job = await queue.add(
      `auto-location-${deviceId}`,
      { deviceId, reason: 'auto_scheduled', scheduledAt: new Date().toISOString() },
      {
        repeat: { cron: '0 */6 * * *' },
        jobId: `auto-location-${deviceId}`
      }
    );

    logger.info(`Auto-location scheduled for device ${deviceId}`, { jobId: job.id });
    return job;
  }

  async cancelAutoLocation(deviceId) {
    const queue = this.getAutoLocationQueue();
    const existingJob = await queue.getRepeatableJobs();
    const existingForDevice = existingJob.find(j => j.name === `auto-location-${deviceId}`);

    if (existingForDevice) {
      await queue.removeRepeatableByKey(existingForDevice.key);
      logger.info(`Auto-location cancelled for device ${deviceId}`);
    }
  }

  async processAutoLocationJob(job) {
    const { deviceId, reason } = job.data;

    try {
      const device = await deviceService.getDeviceById(deviceId);
      if (!device) {
        logger.warn(`Device ${deviceId} not found for auto-location`);
        return;
      }

      const currentLockLevel = device.lock_level || 0;
      if (currentLockLevel < AUTO_LOCK_LEVEL) {
        logger.info(`Device ${deviceId} not in Full Lock — skipping auto-location`);
        await this.cancelAutoLocation(deviceId);
        return;
      }

      await this.pullLocationNow(deviceId, reason || 'auto_location_6h', 'system');

      logger.info(`Auto-location pulled for device ${deviceId}`);
    } catch (error) {
      logger.error(`Auto-location job failed for device ${deviceId}:`, error);
      throw error;
    }
  }

  formatGeofence(row) {
    return {
      id: row.id,
      deviceId: row.device_id,
      name: row.name,
      type: row.type,
      centerLatitude: row.center_latitude,
      centerLongitude: row.center_longitude,
      radiusMeters: row.radius_meters,
      coordinates: row.coordinates ? JSON.parse(row.coordinates) : null,
      enabled: row.enabled,
      createdBy: row.created_by,
      createdByName: row.created_by_name,
      createdAt: row.created_at
    };
  }

  async logAuditEvent({ actor, action, deviceId, metadata = {}, result = 'success' }) {
    try {
      await db.query(
        `INSERT INTO audit_log (actor, action, device_id, metadata, result, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [actor, action, deviceId, JSON.stringify(metadata), result]
      );
    } catch (error) {
      logger.error('Failed to write audit log:', error);
    }
  }

  async initAutoLocationWorker() {
    const queue = this.getAutoLocationQueue();

    queue.process(async (job) => {
      await this.processAutoLocationJob(job);
    });

    logger.info('Auto-location worker initialized');
  }
}

module.exports = new LocationService();