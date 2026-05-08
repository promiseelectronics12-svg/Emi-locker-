import 'package:equatable/equatable.dart';

class LockRequest extends Equatable {
  final String id;
  final String deviceId;
  final String dealerId;
  final String reasonCode;
  final String reasonLabel;
  final String? dealerNote;
  final String status;
  final String? verificationResult;
  final bool fraudFlagged;
  final DateTime createdAt;
  final DateTime? processedAt;

  const LockRequest({
    required this.id,
    required this.deviceId,
    required this.dealerId,
    required this.reasonCode,
    required this.reasonLabel,
    this.dealerNote,
    required this.status,
    this.verificationResult,
    this.fraudFlagged = false,
    required this.createdAt,
    this.processedAt,
  });

  factory LockRequest.fromJson(Map<String, dynamic> json) {
    return LockRequest(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      dealerId: json['dealer_id'] as String,
      reasonCode: json['reason_code'] as String,
      reasonLabel: json['reason_label'] as String,
      dealerNote: json['dealer_note'] as String?,
      status: json['status'] as String,
      verificationResult: json['verification_result'] as String?,
      fraudFlagged: json['fraud_flagged'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'dealer_id': dealerId,
      'reason_code': reasonCode,
      'reason_label': reasonLabel,
      'dealer_note': dealerNote,
      'status': status,
      'verification_result': verificationResult,
      'fraud_flagged': fraudFlagged,
      'created_at': createdAt.toIso8601String(),
      'processed_at': processedAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, deviceId, status];
}

class LockReason {
  final String code;
  final String label;
  final String description;
  final int minOverdueDays;

  const LockReason({
    required this.code,
    required this.label,
    required this.description,
    this.minOverdueDays = 0,
  });

  static const List<LockReason> predefinedReasons = [
    LockReason(
      code: 'M1',
      label: 'Missed 1st Payment',
      description: 'Customer has missed the first EMI payment (1+ days overdue)',
      minOverdueDays: 1,
    ),
    LockReason(
      code: 'M2',
      label: 'Missed 2nd Payment',
      description: 'Customer has missed two consecutive payments (30+ days overdue)',
      minOverdueDays: 30,
    ),
    LockReason(
      code: 'FRAUD',
      label: 'Suspected Fraud',
      description: 'Suspected fraudulent activity or identity theft',
      minOverdueDays: 0,
    ),
    LockReason(
      code: 'TAMPER',
      label: 'Device Tampered',
      description: 'Security hardware or software tampering detected',
      minOverdueDays: 0,
    ),
    LockReason(
      code: 'WILLFUL_DEFAULT',
      label: 'Willful Default',
      description: 'Customer is refusing to pay despite ability',
      minOverdueDays: 7,
    ),
  ];
}