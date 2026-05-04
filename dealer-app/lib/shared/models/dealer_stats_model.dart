class DealerStatsModel {
  final int totalDevices;
  final int activeDevices;
  final int lockedDevices;
  final int pendingDevices;
  final int totalKeys;
  final int availableKeys;
  final int usedKeys;
  final double totalRevenue;
  final double monthlyRevenue;
  final int pendingLockRequests;

  DealerStatsModel({
    required this.totalDevices,
    required this.activeDevices,
    required this.lockedDevices,
    required this.pendingDevices,
    required this.totalKeys,
    required this.availableKeys,
    required this.usedKeys,
    required this.totalRevenue,
    required this.monthlyRevenue,
    required this.pendingLockRequests,
  });

  factory DealerStatsModel.fromJson(Map<String, dynamic> json) {
    return DealerStatsModel(
      totalDevices: json['total_devices'] ?? 0,
      activeDevices: json['active_devices'] ?? 0,
      lockedDevices: json['locked_devices'] ?? 0,
      pendingDevices: json['pending_devices'] ?? 0,
      totalKeys: json['total_keys'] ?? 0,
      availableKeys: json['available_keys'] ?? 0,
      usedKeys: json['used_keys'] ?? 0,
      totalRevenue: double.tryParse(json['total_revenue'].toString()) ?? 0,
      monthlyRevenue: double.tryParse(json['monthly_revenue'].toString()) ?? 0,
      pendingLockRequests: json['pending_lock_requests'] ?? 0,
    );
  }
}
