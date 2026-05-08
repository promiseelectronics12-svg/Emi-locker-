const db = require('../../config/database');
const logger = require('../../utils/logger');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');
const commandSigningService = require('../devices/commandSigningService');
const { createNotificationRecord } = require('../notifications/notification.repository');
const { sendCriticalAlertSMS } = require('../notifications/sms.service');

let _lockService = null;
let _lockDeliveryService = null;
let _lockVerificationService = null;

function getLockService() {
  if (!_lockService) _lockService = require('../lock/lockService').lockService;
  return _lockService;
}

function getLockDeliveryService() {
  if (!_lockDeliveryService) _lockDeliveryService = require('../lock/lockDeliveryService');
  return _lockDeliveryService;
}

function getLockLevels() {
  if (!_lockVerificationService) _lockVerificationService = require('../lock/lockVerificationService');
  return _lockVerificationService.LOCK_LEVELS;
}

const LOCK_LEVELS = {
  NONE: 'NONE',
  REMINDER_MODE: 'REMINDER_MODE',
  PARTIAL_LOCK: 'PARTIAL_LOCK',
  FULL_LOCK: 'FULL_LOCK',
};

const INTEGRITY_FAILURE_TYPES = {
  ROOTED_DEVICE: 'ROOTED_DEVICE',
  TAMPERED_APK: 'TAMPERED_APK',
  UNKNOWN_SOURCES: 'UNKNOWN_SOURCES',
  ATTESTATION_FAILED: 'ATTESTATION_FAILED',
};

const SECURITY_EVENT_TYPES = {
  INTEGRITY_FAILURE: 'INTEGRITY_FAILURE',
  LOCATION_ANOMALY: 'LOCATION_ANOMALY',
  IMEI_MULTIREGISTER: 'IMEI_MULTIREGISTER',
  DEVICE_OFFLINE_OVERDUE: 'DEVICE_OFFLINE_OVERDUE',
  DEALER_FRAUD_RATE: 'DEALER_FRAUD_RATE',
  MANUAL_FLAG: 'MANUAL_FLAG',
};

const SEVERITY_LEVELS = {
  LOW: 'LOW',
  MEDIUM: 'MEDIUM',
  HIGH: 'HIGH',
  CRITICAL: 'CRITICAL',
};

class FraudService {
  async handleIntegrityFailure({ deviceId, failureType, details, nonce, timestamp, signature }) {
    if (!deviceId || !failureType) {
      throw new Error('deviceId and failureType are required');
    }

    const validFailureTypes = Object.values(INTEGRITY_FAILURE_TYPES);
    if (!validFailureTypes.includes(failureType)) {
      throw new Error(`Invalid failure type: ${failureType}`);
    }

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    await this.verifyIntegrityCommandSignature({ deviceId, deviceImei: device.imei, nonce, timestamp, signature });

    const severity = this.determineIntegritySeverity(failureType);

    const securityEventId = await this.createSecurityEvent({
      deviceId,
      eventType: SECURITY_EVENT_TYPES.INTEGRITY_FAILURE,
      severity,
      details: {
        failureType,
        details,
        nonce,
        timestamp,
        signature,
        reportedAt: new Date().toISOString(),
      },
    });

    await this.flagDeviceForNeir(deviceId, `Integrity failure: ${failureType}`);

    if (severity === SEVERITY_LEVELS.CRITICAL || severity === SEVERITY_LEVELS.HIGH) {
      await this.triggerAutoLock(deviceId, `Integrity failure: ${failureType}`);
      await this.alertDealer(deviceId, `Device ${device.imei} failed integrity check (${failureType}). Device has been auto-locked.`);
    }

    await this.logAuditEvent({
      actor: 'system',
      action: 'INTEGRITY_FAILURE_DETECTED',
      deviceId,
      metadata: { failureType, severity, securityEventId },
      result: 'logged',
    });

    return {
      securityEventId,
      severity,
      action: severity >= SEVERITY_LEVELS.HIGH ? 'DEVICE_LOCKED' : 'FLAGGED',
    };
  }

  determineIntegritySeverity(failureType) {
    const severityMap = {
      [INTEGRITY_FAILURE_TYPES.ROOTED_DEVICE]: SEVERITY_LEVELS.CRITICAL,
      [INTEGRITY_FAILURE_TYPES.TAMPERED_APK]: SEVERITY_LEVELS.HIGH,
      [INTEGRITY_FAILURE_TYPES.UNKNOWN_SOURCES]: SEVERITY_LEVELS.MEDIUM,
      [INTEGRITY_FAILURE_TYPES.ATTESTATION_FAILED]: SEVERITY_LEVELS.HIGH,
    };
    return severityMap[failureType] || SEVERITY_LEVELS.MEDIUM;
  }

  async verifyIntegrityCommandSignature({ deviceId, deviceImei, nonce, timestamp, signature }) {

    if (!nonce || !timestamp || !signature) {
      throw new Error('Nonce, timestamp, and signature are required for integrity report');
    }

    if (!commandSigningService.isTimestampValid(timestamp)) {
      throw new Error('Integrity report signature has expired');
    }

    const signedCommand = {
      imei: deviceImei,
      timestamp,
      nonce,
      payload: { deviceId, failureType: 'INTEGRITY_FAILURE' },
      signature,
    };

    try {
      await commandSigningService.verifySignedCommand(deviceId, signedCommand);
    } catch (error) {
      logger.warn(`Integrity command signature verification failed for device ${deviceId}:`, error.message);
      throw new Error('Invalid integrity report signature');
    }
  }

  async triggerAutoLock(deviceId, reason) {
    try {
      const lockService = getLockService();
      const lockDeliveryService = getLockDeliveryService();
      const LOCK_LEVELS = getLockLevels();

      const device = await this.getDeviceById(deviceId);
      if (!device || !device.imei) {
        throw new Error('Device not found');
      }

      const command = await lockService.generateCommand({
        deviceImei: device.imei,
        actionType: 'LOCK',
        lockLevel: LOCK_LEVELS.FULL_LOCK,
        metadata: { reason, source: 'integrity_failure' },
      });

      const delivery = await lockDeliveryService.deliverCommand(deviceId, command, LOCK_LEVELS.FULL_LOCK);

      await db.query(
        `UPDATE devices SET status = 'locked', lock_level = $1, lock_reason = $2, locked_at = NOW(), locked_by = 'system', updated_at = NOW() WHERE id = $3`,
        [LOCK_LEVELS.FULL_LOCK, reason, deviceId]
      );

      await this.logAuditEvent({
        actor: 'system',
        action: 'AUTO_LOCK_TRIGGERED',
        deviceId,
        metadata: { reason, commandNonce: command.nonce, delivery: delivery.results },
        result: 'success',
      });

      return { success: true, action: 'LOCKED' };
    } catch (error) {
      logger.error(`Failed to auto-lock device ${deviceId}:`, error);
      return { success: false, error: error.message };
    }
  }

  async alertDealer(deviceId, message) {
    try {
      const device = await this.getDeviceById(deviceId);
      if (!device || !device.dealer_id) return;

      const dealer = await db.query(
        `SELECT d.id, d.email, d.phone, d.name, u.id as user_id, u.email as user_email
         FROM dealers d
         LEFT JOIN users u ON d.user_id = u.id
         WHERE d.id = $1`,
        [device.dealer_id]
      );

      if (dealer.rows.length === 0) return;

      const dealerData = dealer.rows[0];

      await createNotificationRecord({
        device_id: deviceId,
        type: 'FRAUD_ALERT',
        payload: { message, deviceImei: device.imei, alertType: 'INTEGRITY_FAILURE' },
        status: 'PENDING',
        provider: 'SYSTEM',
      });

      if (dealerData.phone) {
        await sendCriticalAlertSMS(dealerData.phone, message);
      }

      await this.logAuditEvent({
        actor: 'system',
        action: 'DEALER_ALERT_SENT',
        deviceId,
        metadata: { dealerId: device.dealer_id, message },
        result: 'success',
      });

      return { success: true };
    } catch (error) {
      logger.error(`Failed to alert dealer for device ${deviceId}:`, error);
      return { success: false, error: error.message };
    }
  }

  async createSecurityEvent({ deviceId, eventType, severity, details, createdBy }) {
    const validEventTypes = Object.values(SECURITY_EVENT_TYPES);
    if (!eventType || !validEventTypes.includes(eventType)) {
      throw new Error(`Invalid eventType: ${eventType}. Must be one of: ${validEventTypes.join(', ')}`);
    }

    const validSeverities = Object.values(SEVERITY_LEVELS);
    if (!severity || !validSeverities.includes(severity)) {
      throw new Error(`Invalid severity: ${severity}. Must be one of: ${validSeverities.join(', ')}`);
    }

    const eventId = uuidv4();

    const result = await db.query(
      `INSERT INTO security_events (id, device_id, event_type, severity, details, created_by, resolved, resolved_by, resolved_at, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, false, NULL, NULL, NOW())
       RETURNING *`,
      [eventId, deviceId, eventType, severity, JSON.stringify(details), createdBy || 'system']
    );

    await this.logAuditEvent({
      actor: createdBy || 'system',
      action: 'SECURITY_EVENT_CREATED',
      deviceId,
      metadata: { eventId, eventType, severity },
      result: 'success',
    });

    return result.rows[0];
  }

  async resolveSecurityEvent(eventId, resolvedBy, resolution) {
    const event = await this.getSecurityEventById(eventId);
    if (!event) {
      throw new Error('Security event not found');
    }

    if (event.resolved) {
      throw new Error('Security event is already resolved');
    }

    const result = await db.query(
      `UPDATE security_events
       SET resolved = true, resolved_by = $1, resolved_at = NOW(), details = details || $2
       WHERE id = $3
       RETURNING *`,
      [resolvedBy, JSON.stringify({ resolution, resolvedAt: new Date().toISOString() }), eventId]
    );

    if (event.device_id) {
      await this.logAuditEvent({
        actor: resolvedBy,
        action: 'SECURITY_EVENT_RESOLVED',
        deviceId: event.device_id,
        metadata: { eventId, resolution },
        result: 'success',
      });
    }

    return result.rows[0];
  }

  async getSecurityEventById(eventId) {
    const result = await db.query(
      `SELECT se.*, d.imei, d.device_name, d.model, d.brand, d.dealer_id
       FROM security_events se
       LEFT JOIN devices d ON se.device_id = d.id
       WHERE se.id = $1`,
      [eventId]
    );
    return result.rows[0] || null;
  }

  async getSecurityEvents({ page = 1, limit = 20, resolved, severity, eventType, deviceId, dealerId }) {
    const offset = (page - 1) * limit;
    const conditions = [];
    const params = [];
    let paramIndex = 1;

    if (resolved !== undefined) {
      conditions.push(`se.resolved = $${paramIndex++}`);
      params.push(resolved === 'true' || resolved === true);
    }
    if (severity) {
      conditions.push(`se.severity = $${paramIndex++}`);
      params.push(severity);
    }
    if (eventType) {
      conditions.push(`se.event_type = $${paramIndex++}`);
      params.push(eventType);
    }
    if (deviceId) {
      conditions.push(`se.device_id = $${paramIndex++}`);
      params.push(deviceId);
    }
    if (dealerId) {
      conditions.push(`d.dealer_id = $${paramIndex++}`);
      params.push(dealerId);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await db.query(
      `SELECT se.*, d.imei, d.device_name, d.model, d.brand, d.dealer_id,
              dl.name as dealer_name
       FROM security_events se
       LEFT JOIN devices d ON se.device_id = d.id
       LEFT JOIN dealers dl ON d.dealer_id = dl.id
       ${whereClause}
       ORDER BY se.created_at DESC
       LIMIT $${paramIndex++} OFFSET $${paramIndex}`,
      [...params, limit, offset]
    );

    const countResult = await db.query(
      `SELECT COUNT(*) as total FROM security_events se
       LEFT JOIN devices d ON se.device_id = d.id
       ${whereClause}`,
      params
    );

    return {
      events: result.rows,
      pagination: {
        page,
        limit,
        total: parseInt(countResult.rows[0].total, 10),
        pages: Math.ceil(parseInt(countResult.rows[0].total, 10) / limit),
      },
    };
  }

  async flagDeviceForNeir(deviceId, reason) {
    const existing = await db.query(
      `SELECT id FROM neir_report_queue WHERE device_id = $1 AND status IN ('pending', 'flagged')`,
      [deviceId]
    );

    if (existing.rows.length > 0) {
      await db.query(
        `UPDATE neir_report_queue SET reason = $1, updated_at = NOW() WHERE device_id = $2 AND status IN ('pending', 'flagged')`,
        [reason, deviceId]
      );
      return { success: true, action: 'UPDATED' };
    }

    const device = await this.getDeviceById(deviceId);
    if (!device) {
      throw new Error('Device not found');
    }

    await db.query(
      `INSERT INTO neir_report_queue (id, device_id, imei, nid, dealer_id, reason, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, 'pending', NOW())`,
      [uuidv4(), deviceId, device.imei, device.owner_nid, device.dealer_id, reason]
    );

    await this.logAuditEvent({
      actor: 'system',
      action: 'DEVICE_FLAGGED_FOR_NEIR',
      deviceId,
      metadata: { reason },
      result: 'success',
    });

    return { success: true, action: 'CREATED' };
  }

  async getNeirQueue({ page = 1, limit = 20, status, startDate, endDate, cursor }) {
    const conditions = [];
    const params = [];
    let paramIndex = 1;

    if (status) {
      conditions.push(`n.status = $${paramIndex++}`);
      params.push(status);
    }
    if (startDate) {
      conditions.push(`n.created_at >= $${paramIndex++}`);
      params.push(startDate);
    }
    if (endDate) {
      conditions.push(`n.created_at <= $${paramIndex++}`);
      params.push(endDate);
    }
    if (cursor) {
      conditions.push(`n.created_at < $${paramIndex++}`);
      params.push(cursor);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await db.query(
      `SELECT n.*, d.device_name, d.model, d.brand, d.owner_nid,
              dl.name as dealer_name, dl.email as dealer_email
       FROM neir_report_queue n
       LEFT JOIN devices d ON n.device_id = d.id
       LEFT JOIN dealers dl ON n.dealer_id = dl.id
       ${whereClause}
       ORDER BY n.created_at DESC
       LIMIT $${paramIndex++}`,
      [...params, limit + 1]
    );

    const hasMore = result.rows.length > limit;
    if (hasMore) {
      result.rows.pop();
    }

    const nextCursor = hasMore && result.rows.length > 0
      ? result.rows[result.rows.length - 1].created_at
      : null;

    let total;
    if (cursor || startDate || endDate) {
      total = null;
    } else {
      const countResult = await db.query(
        `SELECT COUNT(*) as total FROM neir_report_queue n ${whereClause}`,
        params.slice(0, paramIndex - 2)
      );
      total = parseInt(countResult.rows[0].total, 10);
    }

    return {
      queue: result.rows,
      pagination: {
        page,
        limit,
        total,
        pages: total ? Math.ceil(total / limit) : null,
        hasMore,
        nextCursor,
      },
    };
  }

  async updateNeirQueueStatus(queueId, status, updatedBy) {
    const validStatuses = ['pending', 'flagged', 'submitted', 'rejected'];
    if (!validStatuses.includes(status)) {
      throw new Error(`Invalid status: ${status}`);
    }

    const result = await db.query(
      `UPDATE neir_report_queue SET status = $1, updated_at = NOW(), submitted_by = $2 WHERE id = $3 RETURNING *`,
      [status, updatedBy, queueId]
    );

    if (result.rows.length === 0) {
      throw new Error('NEIR queue entry not found');
    }

    return result.rows[0];
  }

  async detectLocationAnomalies() {
    const result = await db.query(`
      WITH location_jumps AS (
        SELECT
          dl1.device_id,
          dl1.latitude as lat1,
          dl1.longitude as lon1,
          dl1.timestamp as time1,
          dl2.latitude as lat2,
          dl2.longitude as lon2,
          dl2.timestamp as time2,
          6371 * 2 * ASIN(SQRT(
            POWER(SIN((dl2.latitude - dl1.latitude) * PI() / 180 / 2), 2) +
            COS(dl1.latitude * PI() / 180) * COS(dl2.latitude * PI() / 180) *
            POWER(SIN((dl2.longitude - dl1.longitude) * PI() / 180 / 2), 2)
          )) as distance_km,
          EXTRACT(EPOCH FROM (dl2.timestamp - dl1.timestamp)) / 3600 as hours_elapsed
        FROM device_locations dl1
        JOIN device_locations dl2 ON dl1.device_id = dl2.device_id
        JOIN devices d ON dl1.device_id = d.id
        WHERE dl2.timestamp > dl1.timestamp
          AND dl2.timestamp <= dl1.timestamp + INTERVAL '2 hours'
          AND d.lock_level IN ('PARTIAL_LOCK', 'FULL_LOCK', 'REMINDER_MODE')
      )
      SELECT * FROM location_jumps
      WHERE distance_km > 200 AND hours_elapsed < 2
    `);

    const anomalies = result.rows;
    const processedDeviceIds = new Set();

    for (const jump of anomalies) {
      if (processedDeviceIds.has(jump.device_id)) continue;
      processedDeviceIds.add(jump.device_id);

      const existingEvent = await db.query(
        `SELECT id FROM security_events
         WHERE device_id = $1 AND event_type = $2 AND resolved = false
         AND created_at > NOW() - INTERVAL '24 hours'`,
        [jump.device_id, SECURITY_EVENT_TYPES.LOCATION_ANOMALY]
      );

      if (existingEvent.rows.length > 0) continue;

      await this.createSecurityEvent({
        deviceId: jump.device_id,
        eventType: SECURITY_EVENT_TYPES.LOCATION_ANOMALY,
        severity: SEVERITY_LEVELS.HIGH,
        details: {
          type: 'LOCATION_JUMP',
          fromLocation: { lat: jump.lat1, lon: jump.lon1, timestamp: jump.time1 },
          toLocation: { lat: jump.lat2, lon: jump.lon2, timestamp: jump.time2 },
          distanceKm: Math.round(jump.distance_km),
          hoursElapsed: Math.round(jump.hours_elapsed * 100) / 100,
          alert: `Device jumped ${Math.round(jump.distance_km)}km in ${Math.round(jump.hours_elapsed * 60)} minutes while locked`,
        },
      });
    }

    return { detected: anomalies.length, devices: [...processedDeviceIds] };
  }

  async detectMultiImeiRegistration() {
    const result = await db.query(`
      SELECT nid, COUNT(DISTINCT imei) as imei_count, ARRAY_AGG(DISTINCT imei) as imeis
      FROM devices
      WHERE nid IS NOT NULL AND status != 'decoupled'
      GROUP BY nid
      HAVING COUNT(DISTINCT imei) > 1
    `);

    const anomalies = result.rows;
    const processedNids = new Set();

    for (const record of anomalies) {
      if (processedNids.has(record.nid)) continue;
      processedNids.add(record.nid);

      const existingEvent = await db.query(
        `SELECT id FROM security_events
         WHERE event_type = $1 AND resolved = false
         AND details->>'nid' = $2
         AND created_at > NOW() - INTERVAL '24 hours'`,
        [SECURITY_EVENT_TYPES.IMEI_MULTIREGISTER, record.nid]
      );

      if (existingEvent.rows.length > 0) continue;

      const devices = await db.query(
        `SELECT id, imei, device_name, model, dealer_id
         FROM devices WHERE nid = $1 AND imei = ANY($2)`,
        [record.nid, record.imeis]
      );

      await this.createSecurityEvent({
        deviceId: devices.rows[0]?.id,
        eventType: SECURITY_EVENT_TYPES.IMEI_MULTIREGISTER,
        severity: SEVERITY_LEVELS.MEDIUM,
        details: {
          type: 'MULTIPLE_IMEIS_SAME_NID',
          nid: record.nid,
          imeiCount: record.imei_count,
          imeis: record.imeis,
          devices: devices.rows.map(d => ({
            deviceId: d.id,
            imei: d.imei,
            deviceName: d.device_name,
            model: d.model,
            dealerId: d.dealer_id,
          })),
        },
      });
    }

    return { detected: anomalies.length, nids: [...processedNids] };
  }

  async detectOfflineOverdueDevices() {
    const result = await db.query(`
      SELECT d.id as device_id, d.imei, d.device_name, d.last_location_at, d.dealer_id,
             es.status as emi_status, es.id as schedule_id,
             (NOW() - d.last_location_at) as days_offline
      FROM devices d
      JOIN emi_schedules es ON d.id = es.device_id
      WHERE d.status IN ('locked', 'enrolled')
        AND d.last_location_at < NOW() - INTERVAL '30 days'
        AND es.status = 'active'
        AND EXISTS (
          SELECT 1 FROM emi_installments ei
          WHERE ei.schedule_id = es.id
            AND ei.due_date < NOW() - INTERVAL '7 days'
            AND (ei.payment_id IS NULL OR ei.payment_status != 'completed')
        )
    `);

    const anomalies = result.rows;

    for (const device of anomalies) {
      const existingEvent = await db.query(
        `SELECT id FROM security_events
         WHERE device_id = $1 AND event_type = $2 AND resolved = false
         AND created_at > NOW() - INTERVAL '7 days'`,
        [device.device_id, SECURITY_EVENT_TYPES.DEVICE_OFFLINE_OVERDUE]
      );

      if (existingEvent.rows.length > 0) continue;

      await this.createSecurityEvent({
        deviceId: device.device_id,
        eventType: SECURITY_EVENT_TYPES.DEVICE_OFFLINE_OVERDUE,
        severity: SEVERITY_LEVELS.HIGH,
        details: {
          type: 'DEVICE_OFFLINE_OVERDUE',
          imei: device.imei,
          deviceName: device.device_name,
          lastLocationAt: device.last_location_at,
          daysOffline: Math.round(device.days_offline),
          emiScheduleId: device.schedule_id,
          alert: `Device offline for ${Math.round(device.days_offline)} days while EMI overdue`,
        },
      });
    }

    return { detected: anomalies.length };
  }

  async detectDealerFraudFlags() {
    const FRAUD_RATE_THRESHOLD = parseFloat(process.env.DEALER_FRAUD_RATE_THRESHOLD || '0.5');

    const result = await db.query(`
      WITH dealer_fraud_stats AS (
        SELECT
          d.dealer_id,
          COUNT(se.id) as total_events,
          COUNT(CASE WHEN se.resolved = false THEN 1 END) as unresolved_events,
          COUNT(CASE WHEN se.severity IN ('HIGH', 'CRITICAL') THEN 1 END) as high_severity_events,
          dl.name as dealer_name,
          dl.total_devices
        FROM security_events se
        JOIN devices d ON se.device_id = d.id
        JOIN dealers dl ON d.dealer_id = dl.id
        WHERE se.created_at > NOW() - INTERVAL '30 days'
          AND se.event_type != 'MANUAL_FLAG'
        GROUP BY d.dealer_id, dl.name, dl.total_devices
        HAVING COUNT(se.id) >= 5
      )
      SELECT *,
        CASE WHEN total_devices > 0 THEN ROUND((high_severity_events::numeric / total_devices) * 100, 2) ELSE 0 END as fraud_rate
      FROM dealer_fraud_stats
      WHERE (high_severity_events::numeric / NULLIF(total_devices, 0)) >= $1
        OR high_severity_events >= 10
    `, [FRAUD_RATE_THRESHOLD]);

    const anomalies = result.rows;

    for (const dealer of anomalies) {
      const existingEvent = await db.query(
        `SELECT id FROM security_events
         WHERE event_type = $1 AND resolved = false
         AND details->>'dealerId' = $2
         AND created_at > NOW() - INTERVAL '7 days'`,
        [SECURITY_EVENT_TYPES.DEALER_FRAUD_RATE, dealer.dealer_id]
      );

      if (existingEvent.rows.length > 0) continue;

      await this.createSecurityEvent({
        deviceId: null,
        eventType: SECURITY_EVENT_TYPES.DEALER_FRAUD_RATE,
        severity: SEVERITY_LEVELS.HIGH,
        details: {
          type: 'DEALER_HIGH_FRAUD_RATE',
          dealerId: dealer.dealer_id,
          dealerName: dealer.dealer_name,
          totalDevices: dealer.total_devices,
          totalEvents: dealer.total_events,
          highSeverityEvents: dealer.high_severity_events,
          unresolvedEvents: dealer.unresolved_events,
          fraudRate: dealer.fraud_rate,
          alert: `Dealer ${dealer.dealer_name} has ${dealer.fraud_rate}% fraud flag rate`,
        },
        createdBy: 'system',
      });
    }

    return { detected: anomalies.length };
  }

  async runAllAnomalyDetections() {
    // Run all detections in parallel for performance
    const [locationAnomalies, multiImeiRegistration, offlineOverdueDevices, dealerFraudFlags] =
      await Promise.allSettled([
        this.detectLocationAnomalies(),
        this.detectMultiImeiRegistration(),
        this.detectOfflineOverdueDevices(),
        this.detectDealerFraudFlags(),
      ]);

    const results = {
      locationAnomalies: locationAnomalies.status === 'fulfilled'
        ? locationAnomalies.value
        : { detected: 0, error: locationAnomalies.reason?.message },
      multiImeiRegistration: multiImeiRegistration.status === 'fulfilled'
        ? multiImeiRegistration.value
        : { detected: 0, error: multiImeiRegistration.reason?.message },
      offlineOverdueDevices: offlineOverdueDevices.status === 'fulfilled'
        ? offlineOverdueDevices.value
        : { detected: 0, error: offlineOverdueDevices.reason?.message },
      dealerFraudFlags: dealerFraudFlags.status === 'fulfilled'
        ? dealerFraudFlags.value
        : { detected: 0, error: dealerFraudFlags.reason?.message },
      ranAt: new Date().toISOString(),
    };

    const totalDetected = Object.values(results).reduce((sum, r) => {
      if (r && typeof r.detected === 'number') return sum + r.detected;
      return sum;
    }, 0);

    await this.logAuditEvent({
      actor: 'system',
      action: 'ANOMALY_DETECTION_COMPLETE',
      deviceId: null,
      metadata: { ...results, totalDetected },
      result: 'success',
    });

    return results;
  }

  async getAnomalySummary() {
    const summary = await db.query(`
      SELECT
        event_type,
        COUNT(*) as count,
        COUNT(CASE WHEN resolved = false THEN 1 END) as unresolved_count
      FROM security_events
      WHERE created_at > NOW() - INTERVAL '30 days'
      GROUP BY event_type
      ORDER BY count DESC
    `);

    const severitySummary = await db.query(`
      SELECT severity,
             COUNT(*) as count,
             COUNT(CASE WHEN resolved = false THEN 1 END) as unresolved_count
      FROM security_events
      WHERE created_at > NOW() - INTERVAL '30 days'
      GROUP BY severity ORDER BY count DESC
    `);

    const countsByType = {};
    for (const row of summary.rows) {
      countsByType[row.event_type] = parseInt(row.count, 10);
    }

    const bySeverity = {};
    for (const row of severitySummary.rows) {
      bySeverity[row.severity] = {
        total: parseInt(row.count, 10),
        unresolved: parseInt(row.unresolved_count, 10),
      };
    }

    return {
      totalEvents: summary.rows.reduce((s, r) => s + parseInt(r.count, 10), 0),
      byType: {
        locationAnomalies: countsByType[SECURITY_EVENT_TYPES.LOCATION_ANOMALY] || 0,
        multiImeiRegistration: countsByType[SECURITY_EVENT_TYPES.IMEI_MULTIREGISTER] || 0,
        offlineOverdueDevices: countsByType[SECURITY_EVENT_TYPES.DEVICE_OFFLINE_OVERDUE] || 0,
        dealerFraudFlags: countsByType[SECURITY_EVENT_TYPES.DEALER_FRAUD_RATE] || 0,
        integrityFailures: countsByType[SECURITY_EVENT_TYPES.INTEGRITY_FAILURE] || 0,
      },
      bySeverity,
      breakdown: summary.rows,
      period: '30 days',
    };
  }

  // Called when device reports a SIM_CHANGED event.
  // If a location anomaly was also recorded for this device within the last 60 minutes,
  // we have two corroborating signals — escalate immediately.
  async handleSimChangeEvent({ deviceId, lat, lon }) {
    try {
      const device = await this.getDeviceById(deviceId);
      if (!device) return;

      // Check if a location anomaly arrived in the last 60 minutes
      const recentAnomaly = await db.query(
        `SELECT id FROM location_anomalies
         WHERE device_id = $1
           AND detected_at > NOW() - INTERVAL '60 minutes'
           AND alert_type IN ('UNUSUAL_LOCATION', 'IMPOSSIBLE_TRAVEL', 'NEW_REGION', 'RESET_WITH_RELOCATION')
         LIMIT 1`,
        [deviceId]
      );

      const twoSignals = recentAnomaly.rows.length > 0;
      const severity   = twoSignals ? SEVERITY_LEVELS.CRITICAL : SEVERITY_LEVELS.HIGH;

      await this.createSecurityEvent({
        deviceId,
        eventType: SECURITY_EVENT_TYPES.INTEGRITY_FAILURE,
        severity,
        details: {
          type: 'SIM_CHANGE',
          twoSignalRule: twoSignals,
          lat, lon,
        },
      });

      const msg = twoSignals
        ? `CRITICAL: SIM change + location anomaly detected on device ${device.model || device.imei}. Possible theft.`
        : `SIM change detected on device ${device.model || device.imei}. Tap to review.`;

      await this.alertDealer(deviceId, msg);

      if (twoSignals) {
        // Apply credit score penalty for the two-signal fraud combination
        await this._applyCreditPenalty(device, 'ANOMALY_DETECTED');
      }
    } catch (err) {
      logger.error(`handleSimChangeEvent error for device ${deviceId}`, err);
    }
  }

  // Called when device reports a location anomaly.
  // Checks if a SIM change was also reported in the last 60 minutes for the two-signal rule.
  async handleLocationAnomalyEvent({ deviceId, alert_type, area_description }) {
    try {
      const device = await this.getDeviceById(deviceId);
      if (!device) return;

      // Immediately-alerting single signals (no two-signal requirement)
      const criticalAlerts = ['IMPOSSIBLE_TRAVEL', 'RESET_WITH_RELOCATION', 'SIM_CHANGE_RELOCATION'];
      if (criticalAlerts.includes(alert_type)) {
        await this.alertDealer(deviceId,
          `${alert_type.replace(/_/g, ' ')} detected on device ${device.model || device.imei}. Area: ${area_description || 'unknown'}.`
        );
        return;
      }

      // For other alert types, check for a matching SIM change in the last 60 minutes
      const recentSim = await db.query(
        `SELECT id FROM sim_events
         WHERE device_id = $1
           AND event_type = 'SIM_CHANGED'
           AND detected_at > NOW() - INTERVAL '60 minutes'
         LIMIT 1`,
        [deviceId]
      );

      if (recentSim.rows.length > 0) {
        await this.alertDealer(deviceId,
          `Two-signal fraud alert: ${alert_type} + SIM change within 60 min on device ${device.model || device.imei}. Area: ${area_description || 'unknown'}.`
        );
        await this._applyCreditPenalty(device, 'ANOMALY_DETECTED');
      }
      // Single anomaly-only: just logged in location_anomalies, no alert yet
    } catch (err) {
      logger.error(`handleLocationAnomalyEvent error for device ${deviceId}`, err);
    }
  }

  async _applyCreditPenalty(device, eventType) {
    try {
      if (!device.owner_nid) return;
      const creditService = require('../credit/creditScoreService');
      const crypto = require('crypto');
      const nidHash = crypto.createHash('sha256').update(device.owner_nid).digest('hex');
      await creditService.recordPaymentEvent(nidHash, eventType);
    } catch (err) {
      logger.warn('Credit penalty application failed (non-fatal)', err.message);
    }
  }

  async getDeviceById(deviceId) {
    const result = await db.query(
      `SELECT d.*, u.nid as owner_nid
       FROM devices d
       LEFT JOIN users u ON d.owner_id = u.id
       WHERE d.id = $1`,
      [deviceId]
    );
    return result.rows[0] || null;
  }

  async logAuditEvent({ actor, action, deviceId, metadata, result }) {
    try {
      await db.query(
        `INSERT INTO audit_log (actor, action, device_id, metadata, result, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [actor, action, deviceId, JSON.stringify(metadata), result]
      );
    } catch (error) {
      logger.error('Failed to write audit log', { error: error.message });
    }
  }
}

module.exports = new FraudService();