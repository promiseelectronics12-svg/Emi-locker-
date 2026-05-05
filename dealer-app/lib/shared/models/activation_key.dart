import 'package:equatable/equatable.dart';

enum KeyStatus { available, assigned, activated, revoked }

class ActivationKey extends Equatable {
  final String id;
  final String keyCode;
  final String resellerId;
  final String? dealerId;
  final KeyStatus status;
  final DateTime createdAt;
  final DateTime? activatedAt;

  const ActivationKey({
    required this.id,
    required this.keyCode,
    required this.resellerId,
    this.dealerId,
    required this.status,
    required this.createdAt,
    this.activatedAt,
  });

  factory ActivationKey.fromJson(Map<String, dynamic> json) {
    return ActivationKey(
      id: json['id'] as String,
      keyCode: (json['key_string'] ?? json['key_code']) as String,
      resellerId: json['reseller_id'] as String,
      dealerId: json['dealer_id'] as String?,
      status: _parseStatus(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      activatedAt: json['activated_at'] != null ? DateTime.parse(json['activated_at'] as String) : null,
    );
  }

  static KeyStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return KeyStatus.available;
      case 'ASSIGNED':
        return KeyStatus.assigned;
      case 'ACTIVATED':
        return KeyStatus.activated;
      case 'REVOKED':
        return KeyStatus.revoked;
      default:
        return KeyStatus.available;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key_string': keyCode,
      'reseller_id': resellerId,
      'dealer_id': dealerId,
      'status': status.name.toUpperCase(),
      'created_at': createdAt.toIso8601String(),
      'activated_at': activatedAt?.toIso8601String(),
    };
  }

  bool get isValid => status == KeyStatus.available || status == KeyStatus.assigned;
  bool get isAvailable => status == KeyStatus.available || status == KeyStatus.assigned;
  bool get isUsed => status == KeyStatus.activated;
  DateTime? get usedAt => activatedAt;
  String get key => keyCode;
  DateTime get expiresAt => DateTime(9999, 12, 31);

  @override
  List<Object?> get props => [id, keyCode, status];
}
