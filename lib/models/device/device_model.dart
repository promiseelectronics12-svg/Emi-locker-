import 'package:flutter/material.dart';

enum DeviceStatus {
  active,
  reminder,
  partialLock,
  fullLock,
  paidOff,
  compromised,
}

class DeviceModel {
  final String id;
  final String imei;
  final String serial;
  final String oem;
  final String model;
  final String androidVersion;
  final DateTime enrollmentDate;
  final DeviceStatus status;
  final DateTime lastStateChange;
  final double latitude;
  final double longitude;
  final DateTime lastLocationUpdate;
  final List<<EMEMISchedule> emiSchedules;
  final List<<PaymentPaymentRecord> paymentHistory;
  final CustomerInfo customer;

  DeviceModel({
    required this.id,
    required this.imei,
    required this.serial,
    required this.oem,
    required this.model,
    required this.androidVersion,
    required this.enrollmentDate,
    required this.status,
    required this.lastStateChange,
    required this.latitude,
    required this.longitude,
    required this.lastLocationUpdate,
    required this.emiSchedules,
    required this.paymentHistory,
    required this.customer,
  });
}

class EMISchedule {
  final int installmentNumber;
  final double amount;
  final DateTime dueDate;
  final bool isPaid;
  final DateTime? paymentDate;

  EMISchedule({
    required this.installmentNumber,
    required this.amount,
    required this.dueDate,
    required this.isPaid,
    this.paymentDate,
  });
}

class PaymentRecord {
  final String transactionId;
  final double amount;
  final DateTime paymentDate;
  final String method;

  PaymentRecord({
    required this.transactionId,
    required this.amount,
    required this.paymentDate,
    required this.method,
  });
}

class CustomerInfo {
  final String name;
  final String nid;
  final String phone;
  final String nidPhotoUrl;

  CustomerInfo({
    required this.name,
    required this.nid,
    required this.phone,
    required this.nidPhotoUrl,
  });
}
