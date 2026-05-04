import 'package:equatable/equatable.dart';

class ActivationKey extends Equatable {
  final String id;
  final String resellerId;
  final String? dealerId;
  final String keyCode;
  final bool isUsed;
  final DateTime createdAt;
  final DateTime? usedAt;
  final String? deviceId;

  const ActivationKey({
    required this.id,
    required this.resellerId,
    this.dealerId,
    required this.keyCode,
    required this.isUsed,
    required this.createdAt,
    this.usedAt,
    this.deviceId,
  });

  factory ActivationKey.fromJson(Map<String, dynamic> json) {
    return ActivationKey(
      id: json['id'] as String,
      resellerId: json['reseller_id'] as String,
      dealerId: json['dealer_id'] as String?,
      keyCode: json['key_code'] as String,
      isUsed: json['is_used'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      usedAt:
          json['used_at'] != null ? DateTime.parse(json['used_at'] as String) : null,
      deviceId: json['device_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reseller_id': resellerId,
      'dealer_id': dealerId,
      'key_code': keyCode,
      'is_used': isUsed,
      'created_at': createdAt.toIso8601String(),
      'used_at': usedAt?.toIso8601String(),
      'device_id': deviceId,
    };
  }

  @override
  List<Object?> get props => [id, keyCode, isUsed];
}