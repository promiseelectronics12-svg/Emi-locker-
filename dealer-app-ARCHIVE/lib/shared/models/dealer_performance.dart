import 'package:equatable/equatable.dart';

class DealerPerformance extends Equatable {
  final String dealerId;
  final String dealerName;
  final int totalDevices;
  final int activeDevices;
  final int lockedDevices;
  final int pendingLockRequests;
  final int totalKeysAssigned;
  final int totalKeysUsed;
  final double activationRate;
  final double collectionRate;
  final DateTime? lastActivityAt;

  const DealerPerformance({
    required this.dealerId,
    required this.dealerName,
    required this.totalDevices,
    required this.activeDevices,
    required this.lockedDevices,
    required this.pendingLockRequests,
    required this.totalKeysAssigned,
    required this.totalKeysUsed,
    required this.activationRate,
    required this.collectionRate,
    this.lastActivityAt,
  });

  factory DealerPerformance.fromJson(Map<String, dynamic> json) {
    return DealerPerformance(
      dealerId: json['dealer_id'] as String,
      dealerName: json['dealer_name'] as String,
      totalDevices: json['total_devices'] as int? ?? 0,
      activeDevices: json['active_devices'] as int? ?? 0,
      lockedDevices: json['locked_devices'] as int? ?? 0,
      pendingLockRequests: json['pending_lock_requests'] as int? ?? 0,
      totalKeysAssigned: json['total_keys_assigned'] as int? ?? 0,
      totalKeysUsed: json['total_keys_used'] as int? ?? 0,
      activationRate:
          double.tryParse(json['activation_rate']?.toString() ?? '0') ?? 0,
      collectionRate:
          double.tryParse(json['collection_rate']?.toString() ?? '0') ?? 0,
      lastActivityAt: json['last_activity_at'] != null
          ? DateTime.parse(json['last_activity_at'] as String)
          : null,
    );
  }

  int get keysAvailable => totalKeysAssigned - totalKeysUsed;

  @override
  List<Object?> get props => [
        dealerId,
        dealerName,
        totalDevices,
        activeDevices,
        lockedDevices,
        pendingLockRequests,
        totalKeysAssigned,
        totalKeysUsed,
        activationRate,
        collectionRate,
        lastActivityAt,
      ];
}