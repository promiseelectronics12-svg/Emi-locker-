import 'package:equatable/equatable.dart';

class CollectionRate extends Equatable {
  final int thisMonthPaid;
  final int thisMonthTotal;
  final int lastMonthPaid;
  final int lastMonthTotal;

  const CollectionRate({
    required this.thisMonthPaid,
    required this.thisMonthTotal,
    required this.lastMonthPaid,
    required this.lastMonthTotal,
  });

  double get thisMonthRate => thisMonthTotal > 0 ? (thisMonthPaid / thisMonthTotal) * 100 : 0;
  double get lastMonthRate => lastMonthTotal > 0 ? (lastMonthPaid / lastMonthTotal) * 100 : 0;

  factory CollectionRate.fromJson(Map<String, dynamic> json) {
    return CollectionRate(
      thisMonthPaid: json['this_month_paid'] as int? ?? 0,
      thisMonthTotal: json['this_month_total'] as int? ?? 0,
      lastMonthPaid: json['last_month_paid'] as int? ?? 0,
      lastMonthTotal: json['last_month_total'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [thisMonthPaid, thisMonthTotal, lastMonthPaid, lastMonthTotal];
}

class OverdueAgingBucket extends Equatable {
  final String label;
  final int count;
  final int minDays;
  final int maxDays;

  const OverdueAgingBucket({
    required this.label,
    required this.count,
    required this.minDays,
    required this.maxDays,
  });

  factory OverdueAgingBucket.fromJson(Map<String, dynamic> json) {
    return OverdueAgingBucket(
      label: json['label'] as String,
      count: json['count'] as int? ?? 0,
      minDays: json['min_days'] as int? ?? 0,
      maxDays: json['max_days'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [label, count, minDays, maxDays];
}

class DeviceStatusBreakdown extends Equatable {
  final String status;
  final int count;
  final double percentage;

  const DeviceStatusBreakdown({
    required this.status,
    required this.count,
    required this.percentage,
  });

  factory DeviceStatusBreakdown.fromJson(Map<String, dynamic> json) {
    return DeviceStatusBreakdown(
      status: json['status'] as String,
      count: json['count'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [status, count, percentage];
}

class RevenueReport extends Equatable {
  final double expectedThisMonth;
  final double collectedThisMonth;
  final double expectedLastMonth;
  final double collectedLastMonth;

  const RevenueReport({
    required this.expectedThisMonth,
    required this.collectedThisMonth,
    required this.expectedLastMonth,
    required this.collectedLastMonth,
  });

  double get collectionRateThisMonth => expectedThisMonth > 0 ? (collectedThisMonth / expectedThisMonth) * 100 : 0;
  double get collectionRateLastMonth => expectedLastMonth > 0 ? (collectedLastMonth / expectedLastMonth) * 100 : 0;

  factory RevenueReport.fromJson(Map<String, dynamic> json) {
    return RevenueReport(
      expectedThisMonth: (json['expected_this_month'] as num?)?.toDouble() ?? 0.0,
      collectedThisMonth: (json['collected_this_month'] as num?)?.toDouble() ?? 0.0,
      expectedLastMonth: (json['expected_last_month'] as num?)?.toDouble() ?? 0.0,
      collectedLastMonth: (json['collected_last_month'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  List<Object?> get props => [expectedThisMonth, collectedThisMonth, expectedLastMonth, collectedLastMonth];
}

class KeyUsageReport extends Equatable {
  final int totalPurchased;
  final int used;
  final int available;

  const KeyUsageReport({
    required this.totalPurchased,
    required this.used,
    required this.available,
  });

  double get usageRate => totalPurchased > 0 ? (used / totalPurchased) * 100 : 0;

  factory KeyUsageReport.fromJson(Map<String, dynamic> json) {
    return KeyUsageReport(
      totalPurchased: json['total_purchased'] as int? ?? 0,
      used: json['used'] as int? ?? 0,
      available: json['available'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [totalPurchased, used, available];
}

class DealerAnalyticsData extends Equatable {
  final CollectionRate collectionRate;
  final List<OverdueAgingBucket> overdueAging;
  final List<DeviceStatusBreakdown> statusBreakdown;
  final RevenueReport revenueReport;
  final KeyUsageReport keyUsage;
  final int totalDevices;
  final int activeDevices;

  const DealerAnalyticsData({
    required this.collectionRate,
    required this.overdueAging,
    required this.statusBreakdown,
    required this.revenueReport,
    required this.keyUsage,
    required this.totalDevices,
    required this.activeDevices,
  });

  factory DealerAnalyticsData.fromJson(Map<String, dynamic> json) {
    return DealerAnalyticsData(
      collectionRate: CollectionRate.fromJson(json['collection_rate'] as Map<String, dynamic>? ?? {}),
      overdueAging: (json['overdue_aging'] as List<dynamic>?)
              ?.map((e) => OverdueAgingBucket.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      statusBreakdown: (json['status_breakdown'] as List<dynamic>?)
              ?.map((e) => DeviceStatusBreakdown.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      revenueReport: RevenueReport.fromJson(json['revenue_report'] as Map<String, dynamic>? ?? {}),
      keyUsage: KeyUsageReport.fromJson(json['key_usage'] as Map<String, dynamic>? ?? {}),
      totalDevices: json['total_devices'] as int? ?? 0,
      activeDevices: json['active_devices'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        collectionRate,
        overdueAging,
        statusBreakdown,
        revenueReport,
        keyUsage,
        totalDevices,
        activeDevices,
      ];
}

class NeirExportRecord extends Equatable {
  final String imei;
  final String deviceBrand;
  final String deviceModel;
  final String dealerNid;
  final String dealerBusinessName;
  final DateTime registrationDate;

  const NeirExportRecord({
    required this.imei,
    required this.deviceBrand,
    required this.deviceModel,
    required this.dealerNid,
    required this.dealerBusinessName,
    required this.registrationDate,
  });

  factory NeirExportRecord.fromJson(Map<String, dynamic> json) {
    return NeirExportRecord(
      imei: json['imei'] as String? ?? json['imei1'] as String? ?? '',
      deviceBrand: json['device_brand'] as String? ?? 'Unknown',
      deviceModel: json['device_model'] as String? ?? 'Unknown',
      dealerNid: json['dealer_nid'] as String? ?? '',
      dealerBusinessName: json['dealer_business_name'] as String? ?? '',
      registrationDate: json['registration_date'] != null
          ? DateTime.parse(json['registration_date'] as String)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [imei, dealerNid, registrationDate];
}