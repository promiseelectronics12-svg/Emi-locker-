const adminService = require('./adminService');
const adminDeviceService = require('./adminDeviceService');

const adminController = {
  async getDashboardStats(req, res) {
    const stats = await adminService.getDashboardStats();
    res.json({
      success: true,
      data: stats,
      timestamp: new Date().toISOString()
    });
  },

  async getResellers(req, res) {
    const filters = {
      status: req.query.status,
      search: req.query.search,
      limit: req.query.limit ? parseInt(req.query.limit) : 50,
      offset: req.query.offset ? parseInt(req.query.offset) : 0
    };

    const result = await adminService.getResellers(filters);
    res.json({
      success: true,
      data: result.resellers,
      total: result.total,
      filters
    });
  },

  async approveReseller(req, res) {
    const { id } = req.params;
    const result = await adminService.approveReseller(id, req.user.id, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Reseller approved successfully',
      data: result.reseller
    });
  },

  async suspendReseller(req, res) {
    const { id } = req.params;
    const { reason } = req.body;

    const result = await adminService.suspendReseller(id, req.user.id, reason, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Reseller suspended successfully',
      data: result.reseller
    });
  },

  async setResellerQuota(req, res) {
    const { id } = req.params;
    const { monthlyQuota } = req.body;

    const result = await adminService.setResellerQuota(id, monthlyQuota, req.user.id, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Monthly key quota updated successfully',
      data: result.reseller
    });
  },

  async getDevices(req, res) {
    const filters = {
      status: req.query.status,
      dealerId: req.query.dealerId,
      resellerId: req.query.resellerId,
      imei: req.query.imei,
      search: req.query.search,
      emiStatus: req.query.emiStatus,
      limit: req.query.limit ? parseInt(req.query.limit) : 100,
      offset: req.query.offset ? parseInt(req.query.offset) : 0
    };

    const result = await adminDeviceService.getAllDevices(filters);
    res.json({
      success: true,
      data: result.devices,
      total: result.total,
      filters: result.filters
    });
  },

  async lockDevice(req, res) {
    const { id } = req.params;
    const { reason, lockLevel } = req.body;

    const result = await adminDeviceService.lockDevice(id, req.user.id, reason, req.ip, lockLevel);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Device locked successfully',
      data: {
        deviceId: result.device.id,
        status: result.device.status,
        lockReason: reason,
        lockLevel: result.device.lock_level
      }
    });
  },

  async unlockDevice(req, res) {
    const { id } = req.params;
    const { reason } = req.body;

    const result = await adminDeviceService.unlockDevice(id, req.user.id, reason, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Device unlocked successfully',
      data: {
        deviceId: result.device.id,
        status: result.device.status
      }
    });
  },

  async getAuditLog(req, res) {
    const filters = {
      actor: req.query.actor,
      action: req.query.action,
      targetType: req.query.targetType,
      targetId: req.query.targetId,
      ipAddress: req.query.ipAddress,
      startDate: req.query.startDate,
      endDate: req.query.endDate,
      limit: req.query.limit ? parseInt(req.query.limit) : 100,
      offset: req.query.offset ? parseInt(req.query.offset) : 0
    };

    const result = await adminDeviceService.getAuditLog(filters);
    res.json({
      success: true,
      data: result.entries,
      total: result.total,
      limit: result.limit,
      offset: result.offset
    });
  },

  async getSecurityEvents(req, res) {
    const filters = {
      severity: req.query.severity,
      eventType: req.query.eventType,
      startDate: req.query.startDate,
      endDate: req.query.endDate,
      limit: req.query.limit ? parseInt(req.query.limit) : 100,
      offset: req.query.offset ? parseInt(req.query.offset) : 0
    };

    const result = await adminDeviceService.getSecurityEvents(filters);
    res.json({
      success: true,
      data: result.events,
      total: result.total,
      limit: result.limit,
      offset: result.offset
    });
  },

  async addToNeirQueue(req, res) {
    const { deviceId, reason } = req.body;

    const result = await adminDeviceService.addToNeirQueue(deviceId, req.user.id, reason, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Device added to NEIR reporting queue',
      data: result.entry
    });
  },

  async getKeyRequests(req, res) {
    const filters = {
      status: req.query.status,
      resellerId: req.query.resellerId,
      limit: req.query.limit ? parseInt(req.query.limit) : 100,
      offset: req.query.offset ? parseInt(req.query.offset) : 0
    };

    const result = await adminDeviceService.getKeyRequests(filters);
    res.json({
      success: true,
      data: result.requests,
      total: result.total,
      limit: result.limit,
      offset: result.offset
    });
  },

  async approveKeyRequest(req, res) {
    const { id } = req.params;
    const { quantity } = req.body;

    const result = await adminDeviceService.approveKeyRequest(id, quantity, req.user.id, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Key request approved and keys generated',
      data: {
        requestId: result.requestId,
        approvedQuantity: result.approvedQuantity,
        keyCount: result.generatedKeys.length
      }
    });
  },

  async rejectKeyRequest(req, res) {
    const { id } = req.params;
    const { rejectionReason } = req.body;

    const result = await adminDeviceService.rejectKeyRequest(id, rejectionReason, req.user.id, req.ip);

    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    res.json({
      success: true,
      message: 'Key request rejected',
      data: {
        requestId: result.requestId,
        status: 'rejected',
        rejectedAt: result.rejectedAt
      }
    });
  }
};

module.exports = adminController;