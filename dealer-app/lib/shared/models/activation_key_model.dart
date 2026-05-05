import 'package:equatable/equatable.dart';

class ActivationKey extends Equatable {
  final String id;
  final String resellerId;
  final String? dealerId;
  final String keyCode;
  final bool isUsed;
  final String status;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final String? deviceId;

  const ActivationKey({
    required this.id,
    required this.resellerId,
    this.dealerId,
    required this.keyCode,
    this.isUsed = false,
    this.status = 'available',
    required this.createdAt,
    this.activatedAt,
    this.deviceId,
  });

  factory ActivationKey.fromJson(Map<String, dynamic> json) {
    return ActivationKey(
      id: json['id'] as String,
      resellerId: json['reseller_id'] as String,
      dealerId: json['dealer_id'] as String?,
      keyCode: (json['key_string'] ?? json['key_code']) as String,
      status: (json['status'] as String?) ?? 'available',
      isUsed: ((json['status'] as String?) == 'activated') || (json['is_used'] as bool? ?? false),
      createdAt: DateTime.parse(json['created_at'] as String),
      activatedAt:
          json['activated_at'] != null ? DateTime.parse(json['activated_at'] as String) : null,
      deviceId: json['device_id'] as String?,
    );
  }

  DateTime? get usedAt => activatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reseller_id': resellerId,
      'dealer_id': dealerId,
      'key_string': keyCode,
      'is_used': isUsed,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
      'device_id': deviceId,
    };
  }

  @override
  List<Object?> get props => [id, keyCode, isUsed];
}
