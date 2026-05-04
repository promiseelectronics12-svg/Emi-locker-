import 'package:equatable/equatable.dart';

enum KeyStatus { available, used, expired, revoked }

class ActivationKey extends Equatable {
  final String id;
  final String keyCode;
  final String resellerId;
  final String? dealerId;
  final KeyStatus status;
  final DateTime createdAt;
  final DateTime? usedAt;
  final DateTime expiresAt;

  const ActivationKey({
    required this.id,
    required this.keyCode,
    required this.resellerId,
    this.dealerId,
    required this.status,
    required this.createdAt,
    this.usedAt,
    required this.expiresAt,
  });

  factory ActivationKey.fromJson(Map<String, dynamic> json) {
    return ActivationKey(
      id: json['id'] as String,
      keyCode: json['key_code'] as String,
      resellerId: json['reseller_id'] as String,
      dealerId: json['dealer_id'] as String?,
      status: _parseStatus(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      usedAt: json['used_at'] != null ? DateTime.parse(json['used_at'] as String) : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  static KeyStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'AVAILABLE':
        return KeyStatus.available;
      case 'USED':
        return KeyStatus.used;
      case 'EXPIRED':
        return KeyStatus.expired;
      case 'REVOKED':
        return KeyStatus.revoked;
      default:
        return KeyStatus.available;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key_code': keyCode,
      'reseller_id': resellerId,
      'dealer_id': dealerId,
      'status': status.name.toUpperCase(),
      'created_at': createdAt.toIso8601String(),
      'used_at': usedAt?.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };
  }

  bool get isValid => status == KeyStatus.available && DateTime.now().isBefore(expiresAt);

  @override
  List<Object?> get props => [id, keyCode, status];
}