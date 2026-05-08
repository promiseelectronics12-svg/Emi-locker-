import 'package:equatable/equatable.dart';

enum DeviceStatus {
  active,
  reminder,
  partialLock,
  fullLock,
  paidOff,
  compromised,
}

enum LockReason {
  missedPayment,
  fraudulentActivity,
  stolen,
  customerRequest,
  termsViolation,
}

class DeviceModel extends Equatable {
  final String id;
  final String imei1;
  final String imei2;
  final String? macAddress;
  final String dealerId;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerNid;
  final DateTime customerDob;
  final DeviceStatus status;
  final double emiAmount;
  final int emiTenure;
  final double totalAmount;
  final double paidAmount;
  final DateTime nextPaymentDate;
  final DateTime enrollmentDate;
  final DateTime? lockedAt;
  final String? lockedReason;
  final String? lockedNote;
  final DateTime? lastSyncAt;
  final String? currentLocation;
  final bool hasPautToken;
  final DateTime? poutExpiry;
  final String? nidPhotoUrl;
  final String? oem;
  final String? model;
  final String? androidVersion;
  final DateTime? lastLocationUpdate;
  final double? lastLatitude;
  final double? lastLongitude;

  const DeviceModel({
    required this.id,
    required this.imei1,
    required this.imei2,
    this.macAddress,
    required this.dealerId,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerNid,
    required this.customerDob,
    required this.status,
    required this.emiAmount,
    required this.emiTenure,
    required this.totalAmount,
    required this.paidAmount,
    required this.nextPaymentDate,
    required this.enrollmentDate,
    this.lockedAt,
    this.lockedReason,
    this.lockedNote,
    this.lastSyncAt,
    this.currentLocation,
    this.hasPautToken = false,
    this.poutExpiry,
    this.nidPhotoUrl,
    this.oem,
    this.model,
    this.androidVersion,
    this.lastLocationUpdate,
    this.lastLatitude,
    this.lastLongitude,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      imei1: json['imei1'] as String,
      imei2: json['imei2'] as String? ?? '',
      macAddress: json['mac_address'] as String?,
      dealerId: json['dealer_id'] as String,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String,
      customerNid: json['customer_nid'] as String,
      customerDob: DateTime.parse(json['customer_dob'] as String),
      status: _parseStatus(json['status'] as String),
      emiAmount: (json['emi_amount'] as num).toDouble(),
      emiTenure: json['emi_tenure'] as int,
      totalAmount: (json['total_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      nextPaymentDate: DateTime.parse(json['next_payment_date'] as String),
      enrollmentDate: DateTime.parse(json['enrollment_date'] as String),
      lockedAt: json['locked_at'] != null
          ? DateTime.parse(json['locked_at'] as String)
          : null,
      lockedReason: json['locked_reason'] as String?,
      lockedNote: json['locked_note'] as String?,
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      currentLocation: json['current_location'] as String?,
      hasPautToken: json['has_paut_token'] as bool? ?? false,
      poutExpiry: json['pout_expiry'] != null
          ? DateTime.parse(json['pout_expiry'] as String)
          : null,
      nidPhotoUrl: json['nid_photo_url'] as String?,
      oem: json['oem'] as String?,
      model: json['model'] as String?,
      androidVersion: json['android_version'] as String?,
      lastLocationUpdate: json['last_location_update'] != null
          ? DateTime.parse(json['last_location_update'] as String)
          : null,
      lastLatitude: (json['last_latitude'] as num?)?.toDouble(),
      lastLongitude: (json['last_longitude'] as num?)?.toDouble(),
    );
  }

  static DeviceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return DeviceStatus.active;
      case 'REMINDER':
        return DeviceStatus.reminder;
      case 'PARTIAL_LOCK':
        return DeviceStatus.partialLock;
      case 'FULL_LOCK':
        return DeviceStatus.fullLock;
      case 'PAID_OFF':
        return DeviceStatus.paidOff;
      case 'COMPROMISED':
        return DeviceStatus.compromised;
      default:
        return DeviceStatus.active;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imei1': imei1,
      'imei2': imei2,
      'mac_address': macAddress,
      'dealer_id': dealerId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_nid': customerNid,
      'customer_dob': customerDob.toIso8601String(),
      'status': status.name.toUpperCase(),
      'emi_amount': emiAmount,
      'emi_tenure': emiTenure,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'next_payment_date': nextPaymentDate.toIso8601String(),
      'enrollment_date': enrollmentDate.toIso8601String(),
      'locked_at': lockedAt?.toIso8601String(),
      'locked_reason': lockedReason,
      'locked_note': lockedNote,
      'last_sync_at': lastSyncAt?.toIso8601String(),
      'current_location': currentLocation,
      'has_paut_token': hasPautToken,
      'pout_expiry': poutExpiry?.toIso8601String(),
      'last_location_update': lastLocationUpdate?.toIso8601String(),
      'last_latitude': lastLatitude,
      'last_longitude': lastLongitude,
    };
  }

  int get remainingEmis => emiTenure - (paidAmount / emiAmount).floor();

  double get progressPercentage => (paidAmount / totalAmount) * 100;

  bool get isPaymentOverdue =>
      DateTime.now().isAfter(nextPaymentDate) && status == DeviceStatus.active;

  bool get isPaidOff => status == DeviceStatus.paidOff;

  double get remainingAmount => totalAmount - paidAmount;

  int get overdueDays {
    if (status != DeviceStatus.active && status != DeviceStatus.reminder) return 0;
    final now = DateTime.now();
    if (now.isAfter(nextPaymentDate)) {
      return now.difference(nextPaymentDate).inDays;
    }
    return 0;
  }

  @override
  List<Object?> get props => [id, imei1, status];
}