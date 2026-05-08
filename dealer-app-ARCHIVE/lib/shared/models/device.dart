import 'package:equatable/equatable.dart';

enum DeviceStatus {
  active,
  reminder,
  partialLock,
  fullLock,
  paidOff,
  compromised,
}

class Device extends Equatable {
  final String id;
  final String imei1;
  final String imei2;
  final String serial;
  final String oem;
  final String model;
  final String androidVersion;
  final String macAddress;
  final String customerName;
  final String customerPhone;
  final String customerNid;
  final String? customerNidPhotoUrl;
  final DateTime customerDob;
  final String dealerId;
  final String? resellerId;
  final DeviceStatus status;
  final double emiAmount;
  final int totalInstallments;
  final int paidInstallments;
  final DateTime nextPaymentDate;
  final DateTime? lockedAt;
  final DateTime? lastStateChangeAt;
  final String? lockReason;
  final DateTime? gracePeriodEnd;
  final String? decoupleToken;
  final DateTime enrolledAt;
  final Map<String, dynamic>? lastLocation;
  final List<EmiInstallment>? emiSchedule;
  final List<PaymentRecord>? paymentHistory;

  const Device({
    required this.id,
    required this.imei1,
    this.imei2 = '',
    this.serial = '',
    this.oem = '',
    this.model = '',
    this.androidVersion = '',
    this.macAddress = '',
    required this.customerName,
    required this.customerPhone,
    required this.customerNid,
    this.customerNidPhotoUrl,
    required this.customerDob,
    required this.dealerId,
    this.resellerId,
    required this.status,
    required this.emiAmount,
    required this.totalInstallments,
    required this.paidInstallments,
    required this.nextPaymentDate,
    this.lockedAt,
    this.lastStateChangeAt,
    this.lockReason,
    this.gracePeriodEnd,
    this.decoupleToken,
    required this.enrolledAt,
    this.lastLocation,
    this.emiSchedule,
    this.paymentHistory,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      imei1: json['imei1'] as String,
      imei2: json['imei2'] as String? ?? '',
      serial: json['serial'] as String? ?? '',
      oem: json['oem'] as String? ?? '',
      model: json['model'] as String? ?? '',
      androidVersion: json['android_version'] as String? ?? '',
      macAddress: json['mac_address'] as String? ?? '',
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String,
      customerNid: json['customer_nid'] as String,
      customerNidPhotoUrl: json['customer_nid_photo_url'] as String?,
      customerDob: DateTime.parse(json['customer_dob'] as String),
      dealerId: json['dealer_id'] as String,
      resellerId: json['reseller_id'] as String?,
      status: _parseStatus(json['status'] as String),
      emiAmount: (json['emi_amount'] as num).toDouble(),
      totalInstallments: json['total_installments'] as int,
      paidInstallments: json['paid_installments'] as int,
      nextPaymentDate: DateTime.parse(json['next_payment_date'] as String),
      lockedAt: json['locked_at'] != null
          ? DateTime.parse(json['locked_at'] as String)
          : null,
      lastStateChangeAt: json['last_state_change_at'] != null
          ? DateTime.parse(json['last_state_change_at'] as String)
          : null,
      lockReason: json['lock_reason'] as String?,
      gracePeriodEnd: json['grace_period_end'] != null
          ? DateTime.parse(json['grace_period_end'] as String)
          : null,
      decoupleToken: json['decouple_token'] as String?,
      enrolledAt: DateTime.parse(json['enrolled_at'] as String),
      lastLocation: json['last_location'] as Map<String, dynamic>?,
      emiSchedule: (json['emi_schedule'] as List?)
          ?.map((e) => EmiInstallment.fromJson(e))
          .toList(),
      paymentHistory: (json['payment_history'] as List?)
          ?.map((e) => PaymentRecord.fromJson(e))
          .toList(),
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
      'serial': serial,
      'oem': oem,
      'model': model,
      'android_version': androidVersion,
      'mac_address': macAddress,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_nid': customerNid,
      'customer_nid_photo_url': customerNidPhotoUrl,
      'customer_dob': customerDob.toIso8601String(),
      'dealer_id': dealerId,
      'reseller_id': resellerId,
      'status': status.name.toUpperCase(),
      'emi_amount': emiAmount,
      'total_installments': totalInstallments,
      'paid_installments': paidInstallments,
      'next_payment_date': nextPaymentDate.toIso8601String(),
      'locked_at': lockedAt?.toIso8601String(),
      'last_state_change_at': lastStateChangeAt?.toIso8601String(),
      'lock_reason': lockReason,
      'grace_period_end': gracePeriodEnd?.toIso8601String(),
      'decouple_token': decoupleToken,
      'enrolled_at': enrolledAt.toIso8601String(),
      'last_location': lastLocation,
      'emi_schedule': emiSchedule?.map((e) => e.toJson()).toList(),
      'payment_history': paymentHistory?.map((e) => e.toJson()).toList(),
    };
  }

  double get remainingAmount => emiAmount * (totalInstallments - paidInstallments);
  double get paidAmount => emiAmount * paidInstallments;
  bool get isPaymentOverdue => DateTime.now().isAfter(nextPaymentDate);

  @override
  List<Object?> get props => [id, imei1, status];
}

class EmiInstallment extends Equatable {
  final int installmentNumber;
  final double amount;
  final DateTime dueDate;
  final bool isPaid;
  final DateTime? paidDate;

  const EmiInstallment({
    required this.installmentNumber,
    required this.amount,
    required this.dueDate,
    required this.isPaid,
    this.paidDate,
  });

  factory EmiInstallment.fromJson(Map<String, dynamic> json) {
    return EmiInstallment(
      installmentNumber: json['installment_number'] as int,
      amount: (json['amount'] as num).toDouble(),
      dueDate: DateTime.parse(json['due_date'] as String),
      isPaid: json['is_paid'] as bool,
      paidDate: json['paid_date'] != null
          ? DateTime.parse(json['paid_date'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'installment_number': installmentNumber,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'is_paid': isPaid,
      'paid_date': paidDate?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [installmentNumber, amount, dueDate, isPaid];
}

class PaymentRecord extends Equatable {
  final String id;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String transactionId;

  const PaymentRecord({
    required this.id,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    required this.transactionId,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    return PaymentRecord(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentDate: DateTime.parse(json['payment_date'] as String),
      paymentMethod: json['payment_method'] as String,
      transactionId: json['transaction_id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'payment_date': paymentDate.toIso8601String(),
      'payment_method': paymentMethod,
      'transaction_id': transactionId,
    };
  }

  @override
  List<Object?> get props => [id, amount, paymentDate, transactionId];
}