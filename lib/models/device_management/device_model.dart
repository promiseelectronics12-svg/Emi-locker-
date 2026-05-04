import 'package:flutter/material.dart';

class Device {
  final String id;
  final String imei;
  final String serial;
  final String oem;
  final String model;
  final String androidVersion;
  final String enrollmentDate;
  final String status; // Active, Reminder, Partial Lock, Full Lock, Paid Off, Compromised
  final String lastStateChange;
  final double lastLat;
  final double lastLng;
  final String lastLocationTime;
  final String customerName;
  final String customerNid;
  final String customerPhone;
  final List<<EMIEMIInstallment> emiSchedule;
  final double nextPaymentAmount;
  final String nextPaymentDate;
  final int overdueDays;

  Device({
    required this.id,
    required this.imei,
    required this.serial,
    required this.oem,
    required this.model,
    required this.androidVersion,
    required this.enrollmentDate,
    required this.status,
    required this.lastStateChange,
    required this.lastLat,
    required this.lastLng,
    required this.lastLocationTime,
    required this.customerName,
    required this.customerNid,
    required this.customerPhone,
    required this.emiSchedule,
    required this.nextPaymentAmount,
    required this.nextPaymentDate,
    required this.overdueDays,
  });
}

class EMIInstallment {
  final double amount;
  final String status; // Paid, Unpaid, Partial
  final String dueDate;

  EMIInstallment({
    required this.amount,
    required this.status,
    required this.dueDate,
  });
}
