import 'package:equatable/equatable.dart';

class DealerAnalytics extends Equatable {
  final int totalDevices;
  final int activeDevices;
  final int lockedDevices;
  final int gracePeriodDevices;
  final int decoupledDevices;
  final double totalEmiCollected;
  final double totalEmiPending;
  final double monthlyCollection;
  final List<MonthlyData> monthlyTrend;
  final List<DeviceStatusCount> statusBreakdown;

  const DealerAnalytics({
    required this.totalDevices,
    required this.activeDevices,
    required this.lockedDevices,
    required this.gracePeriodDevices,
    required this.decoupledDevices,
    required this.totalEmiCollected,
    required this.totalEmiPending,
    required this.monthlyCollection,
    required this.monthlyTrend,
    required this.statusBreakdown,
  });

  factory DealerAnalytics.fromJson(Map<String, dynamic> json) {
    return DealerAnalytics(
      totalDevices: json['total_devices'] as int,
      activeDevices: json['active_devices'] as int,
      lockedDevices: json['locked_devices'] as int,
      gracePeriodDevices: json['grace_period_devices'] as int,
      decoupledDevices: json['decoupled_devices'] as int,
      totalEmiCollected: (json['total_emi_collected'] as num).toDouble(),
      totalEmiPending: (json['total_emi_pending'] as num).toDouble(),
      monthlyCollection: (json['monthly_collection'] as num).toDouble(),
      monthlyTrend: (json['monthly_trend'] as List<dynamic>)
          .map((e) => MonthlyData.fromJson(e as Map<String, dynamic>))
          .toList(),
      statusBreakdown: (json['status_breakdown'] as List<dynamic>)
          .map((e) => DeviceStatusCount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [totalDevices, activeDevices, lockedDevices];
}

class MonthlyData extends Equatable {
  final String month;
  final int year;
  final double collected;
  final int newEnrollments;

  const MonthlyData({
    required this.month,
    required this.year,
    required this.collected,
    required this.newEnrollments,
  });

  factory MonthlyData.fromJson(Map<String, dynamic> json) {
    return MonthlyData(
      month: json['month'] as String,
      year: json['year'] as int,
      collected: (json['collected'] as num).toDouble(),
      newEnrollments: json['new_enrollments'] as int,
    );
  }

  @override
  List<Object?> get props => [month, year];
}

class DeviceStatusCount extends Equatable {
  final String status;
  final int count;

  const DeviceStatusCount({
    required this.status,
    required this.count,
  });

  factory DeviceStatusCount.fromJson(Map<String, dynamic> json) {
    return DeviceStatusCount(
      status: json['status'] as String,
      count: json['count'] as int,
    );
  }

  @override
  List<Object?> get props => [status, count];
}

class NeirDeviceRecord extends Equatable {
  final String imei;
  final String deviceModel;
  final String customerName;
  final String customerNid;
  final String customerPhone;
  final double emiAmount;
  final int totalInstallments;
  final int paidInstallments;
  final String enrollmentDate;
  final String status;

  const NeirDeviceRecord({
    required this.imei,
    required this.deviceModel,
    required this.customerName,
    required this.customerNid,
    required this.customerPhone,
    required this.emiAmount,
    required this.totalInstallments,
    required this.paidInstallments,
    required this.enrollmentDate,
    required this.status,
  });

  @override
  List<Object?> get props => [imei, customerNid];
}