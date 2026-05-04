import 'package:equatable/equatable.dart';

class ResellerStats extends Equatable {
  final int totalKeys;
  final int keysPurchased;
  final int keysAssigned;
  final int keysAvailable;
  final int totalDealers;
  final int activeDealers;
  final int pendingDealers;
  final int suspendedDealers;
  final int monthlyQuota;
  final int keysUsedThisMonth;
  final double activationRate;
  final double collectionRate;
  final DateTime? lastKeyRequestAt;
  final int pendingKeyRequests;

  const ResellerStats({
    required this.totalKeys,
    required this.keysPurchased,
    required this.keysAssigned,
    required this.keysAvailable,
    required this.totalDealers,
    required this.activeDealers,
    required this.pendingDealers,
    required this.suspendedDealers,
    required this.monthlyQuota,
    required this.keysUsedThisMonth,
    required this.activationRate,
    required this.collectionRate,
    this.lastKeyRequestAt,
    required this.pendingKeyRequests,
  });

  factory ResellerStats.fromJson(Map<String, dynamic> json) {
    return ResellerStats(
      totalKeys: json['total_keys'] as int? ?? 0,
      keysPurchased: json['keys_purchased'] as int? ?? 0,
      keysAssigned: json['keys_assigned'] as int? ?? 0,
      keysAvailable: json['keys_available'] as int? ?? 0,
      totalDealers: json['total_dealers'] as int? ?? 0,
      activeDealers: json['active_dealers'] as int? ?? 0,
      pendingDealers: json['pending_dealers'] as int? ?? 0,
      suspendedDealers: json['suspended_dealers'] as int? ?? 0,
      monthlyQuota: json['monthly_quota'] as int? ?? 0,
      keysUsedThisMonth: json['keys_used_this_month'] as int? ?? 0,
      activationRate:
          double.tryParse(json['activation_rate']?.toString() ?? '0') ?? 0,
      collectionRate:
          double.tryParse(json['collection_rate']?.toString() ?? '0') ?? 0,
      lastKeyRequestAt: json['last_key_request_at'] != null
          ? DateTime.parse(json['last_key_request_at'] as String)
          : null,
      pendingKeyRequests: json['pending_key_requests'] as int? ?? 0,
    );
  }

  double get quotaUsedPercentage {
    if (monthlyQuota == 0) return 0;
    return (keysUsedThisMonth / monthlyQuota) * 100;
  }

  int get remainingQuota => monthlyQuota - keysUsedThisMonth;

  @override
  List<Object?> get props => [
        totalKeys,
        keysPurchased,
        keysAssigned,
        keysAvailable,
        totalDealers,
        activeDealers,
        pendingDealers,
        suspendedDealers,
        monthlyQuota,
        keysUsedThisMonth,
        activationRate,
        collectionRate,
        lastKeyRequestAt,
        pendingKeyRequests,
      ];
}