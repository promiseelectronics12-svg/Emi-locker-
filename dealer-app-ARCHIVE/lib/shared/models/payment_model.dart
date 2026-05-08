import 'package:equatable/equatable.dart';

class PaymentModel extends Equatable {
  final String id;
  final String deviceId;
  final double amount;
  final int monthNumber;
  final DateTime paidAt;
  final String? paymentMethod;
  final String? transactionRef;
  final String? collectedBy;
  final String? notes;

  const PaymentModel({
    required this.id,
    required this.deviceId,
    required this.amount,
    required this.monthNumber,
    required this.paidAt,
    this.paymentMethod,
    this.transactionRef,
    this.collectedBy,
    this.notes,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    return PaymentModel(
      id: json['id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      monthNumber: json['month_number'] as int? ?? 0,
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: json['payment_method'] as String?,
      transactionRef: json['transaction_ref'] as String?,
      collectedBy: json['collected_by'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'amount': amount,
      'month_number': monthNumber,
      'paid_at': paidAt.toIso8601String(),
      'payment_method': paymentMethod,
      'transaction_ref': transactionRef,
      'collected_by': collectedBy,
      'notes': notes,
    };
  }

  @override
  List<Object?> get props => [id, deviceId, monthNumber, paidAt];
}