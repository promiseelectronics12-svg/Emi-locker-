const fraudService = require('./fraudService');
const logger = require('../../utils/logger');

function validateIntegrityReport(body) {
  const errors = [];
  if (!body.deviceId) errors.push('deviceId is required');
  if (!body.failureType) errors.push('failureType is required');
  if (body.failureType && !['ROOTED_DEVICE', 'TAMPERED_APK', 'UNKNOWN_SOURCES', 'ATTESTATION_FAILED'].includes(body.failureType)) {
    errors.push('Invalid failureType');
  }
  return errors;
}

async function handleIntegrityReport(req, res) {
  try {
    const validationErrors = validateIntegrityReport(req.body);
    if (validationErrors.length > 0) {
      return res.status(400).json({ success: false, errors: validationErrors });
    }

    const { deviceId, failureType, details, nonce, timestamp, signature } = req.body;

    const result = await fraudService.handleIntegrityFailure({
      deviceId,
      failureType,
      details: details || {},
      nonce,
      timestamp,
      signature,
    });

    res.json({
      success: true,
      securityEventId: result.securityEventId,
      severity: result.severity,
      action: result.action,
    });
  } catch (error) {
    logger.error('Error handling integrity report:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

async function createSecurityEvent(req, res) {
  try {
    const { deviceId, eventType, severity, details } = req.body;

    if (!deviceId) {
      return res.status(400).json({ success: false, error: 'deviceId is required' });
    }
    if (!eventType) {
      return res.status(400).json({ success: false, error: 'eventType is required' });
    }
    if (!severity) {
      return res.status(400).json({ success: false, error: 'severity is required' });
    }

    const validSeverities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
    if (!validSeverities.includes(severity)) {
      return res.status(400).json({ success: false, error: 'Invalid severity level' });
    }

    const event = await fraudService.createSecurityEvent({
      deviceId,
      eventType,
      severity,
      details: details || {},
      createdBy: req.user?.id || 'system',
    });

    res.status(201).json({ success: true, event });
  } catch (error) {
    logger.error('Error creating security event:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

async function resolveSecurityEvent(req, res) {
  try {
    const { eventId } = req.params;
    const { resolution } = req.body;

    if (!resolution) {
      return res.status(400).json({ success: false, error: 'resolution is required' });
    }

    const resolvedEvent = await fraudService.resolveSecurityEvent(
      eventId,
      req.user?.id || 'admin',
      resolution
    );

    res.json({ success: true, event: resolvedEvent });
  } catch (error) {
    logger.error('Error resolving security event:', error);
    if (error.message === 'Security event not found') {
      return res.status(404).json({ success: false, error: error.message });
    }
    if (error.message === 'Security event is already resolved') {
      return res.status(409).json({ success: false, error: error.message });
    }
    res.status(500).json({ success: false, error: error.message });
  }
}

async function getSecurityEvents(req, res) {
  try {
    const { page = 1, limit = 20, resolved, severity, eventType, deviceId, dealerId } = req.query;

    const result = await fraudService.getSecurityEvents({
      page: parseInt(page, 10),
      limit: parseInt(limit, 10),
      resolved,
      severity,
      eventType,
      deviceId,
      dealerId,
    });

    res.json({ success: true, ...result });
  } catch (error) {
    logger.error('Error fetching security events:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

async function getSecurityEvent(req, res) {
  try {
    const { eventId } = req.params;
    const event = await fraudService.getSecurityEventById(eventId);

    if (!event) {
      return res.status(404).json({ success: false, error: 'Security event not found' });
    }

    res.json({ success: true, event });
  } catch (error) {
    logger.error('Error fetching security event:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

async function getNeirQueue(req, res) {
  try {
    const { page = 1, limit = 20, status } = req.query;

    const result = await fraudService.getNeirQueue({
      page: parseInt(page, 10),
      limit: parseInt(limit, 10),
      status,
    });

    res.json({ success: true, ...result });
  } catch (error) {
    logger.error('Error fetching NEIR queue:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

async function exportNeirReport(req, res) {
  try {
    const { status, startDate, endDate, limit: queryLimit } = req.query;
    const BATCH_SIZE = 1000;
    const MAX_RECORDS = parseInt(queryLimit, 10) || 10000;

    const excel = require('exceljs');
    const workbook = new excel.Workbook();
    const worksheet = workbook.addWorksheet('NEIR Report');

    worksheet.columns = [
      { header: 'IMEI', key: 'imei', width: 20 },
      { header: 'NID', key: 'nid', width: 20 },
      { header: 'Device Name', key: 'deviceName', width: 25 },
      { header: 'Model', key: 'model', width: 20 },
      { header: 'Brand', key: 'brand', width: 15 },
      { header: 'Dealer Name', key: 'dealerName', width: 25 },
      { header: 'Dealer Email', key: 'dealerEmail', width: 30 },
      { header: 'Reason', key: 'reason', width: 40 },
      { header: 'Status', key: 'status', width: 15 },
      { header: 'Flagged Date', key: 'createdAt', width: 20 },
    ];

    worksheet.getRow(1).font = { bold: true };
    worksheet.getRow(1).fill = { type: 'patternFill', pattern: 'solid', fgColor: { argb: 'FFD9E1F2' } };

    let cursor = null;
    let totalExported = 0;
    let hasMore = true;

    while (hasMore && totalExported < MAX_RECORDS) {
      const batchLimit = Math.min(BATCH_SIZE, MAX_RECORDS - totalExported);

      const result = await fraudService.getNeirQueue({
        cursor,
        status: status || 'pending',
        startDate,
        endDate,
        limit: batchLimit,
      });

      const excelData = generateNeirExcelData(result.queue);
      excelData.forEach(row => worksheet.addRow(row));

      totalExported += result.queue.length;
      cursor = result.pagination.nextCursor;
      hasMore = result.pagination.hasMore;
    }

    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename=NEIR_Report_${new Date().toISOString().split('T')[0]}.xlsx`);

    await workbook.xlsx.write(res);
    res.end();
  } catch (error) {
    logger.error('Error exporting NEIR report:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

function generateNeirExcelData(queueItems) {
  return queueItems.map(item => ({
    imei: item.imei || '',
    nid: item.nid || item.owner_nid || '',
    deviceName: item.device_name || '',
    model: item.model || '',
    brand: item.brand || '',
    dealerName: item.dealer_name || '',
    dealerEmail: item.dealer_email || '',
    reason: item.reason || '',
    status: item.status || '',
    createdAt: item.created_at ? new Date(item.created_at).toISOString().split('T')[0] : '',
  }));
}

async function getAnomalySummary(req, res) {
  try {
    const summary = await fraudService.getAnomalySummary();
    res.json({ success: true, summary });
  } catch (error) {
    logger.error('Error fetching anomaly summary:', error);
    res.status(500).json({ success: false, error: 'Internal server error' });
  }
}

module.exports = {
  handleIntegrityReport,
  createSecurityEvent,
  resolveSecurityEvent,
  getSecurityEvents,
  getSecurityEvent,
  getNeirQueue,
  exportNeirReport,
  getAnomalySummary,
};