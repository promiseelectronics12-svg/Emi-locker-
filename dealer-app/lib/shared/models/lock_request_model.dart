import 'package:equatable/equatable.dart';

enum LockRequestStatus {
  pending,
  verified,
  rejected,
  executed,
  cancelled,
}

class LockRequest extends Equatable {
  final String id;
  final String deviceId;
  final String dealerId;
  final String reasonCode;
  final String? dealerNote;
  final LockRequestStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final DateTime? executedAt;
  final String? adminId;

  const LockRequest({
    required this.id,
    required this.deviceId,
    required this.dealerId,
    required this.reasonCode,
    this.dealerNote,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.verifiedAt,
    this.executedAt,
    this.adminId,
  });

  factory LockRequest.fromJson(Map<String, dynamic> json) {
    return LockRequest(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      dealerId: json['dealer_id'] as String,
      reasonCode: json['reason_code'] as String,
      dealerNote: json['dealer_note'] as String?,
      status: _parseStatus(json['status'] as String),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      executedAt: json['executed_at'] != null
          ? DateTime.parse(json['executed_at'] as String)
          : null,
      adminId: json['admin_id'] as String?,
    );
  }

  static LockRequestStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return LockRequestStatus.pending;
      case 'VERIFIED':
        return LockRequestStatus.verified;
      case 'REJECTED':
        return LockRequestStatus.rejected;
      case 'EXECUTED':
        return LockRequestStatus.executed;
      case 'CANCELLED':
        return LockRequestStatus.cancelled;
      default:
        return LockRequestStatus.pending;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'dealer_id': dealerId,
      'reason_code': reasonCode,
      'dealer_note': dealerNote,
      'status': status.name.toUpperCase(),
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'verified_at': verifiedAt?.toIso8601String(),
      'executed_at': executedAt?.toIso8601String(),
      'admin_id': adminId,
    };
  }

  @override
  List<Object?> get props => [id, deviceId, status];
}