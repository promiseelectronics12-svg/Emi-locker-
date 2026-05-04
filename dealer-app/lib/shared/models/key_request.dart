import 'package:equatable/equatable.dart';

enum KeyRequestStatus { pending, approved, rejected }

class KeyRequest extends Equatable {
  final String id;
  final String resellerId;
  final int quantity;
  final String justification;
  final KeyRequestStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const KeyRequest({
    required this.id,
    required this.resellerId,
    required this.quantity,
    required this.justification,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.reviewedAt,
  });

  factory KeyRequest.fromJson(Map<String, dynamic> json) {
    return KeyRequest(
      id: json['id'] as String,
      resellerId: json['reseller_id'] as String,
      quantity: json['quantity'] as int,
      justification: json['justification'] as String,
      status: _parseStatus(json['status'] as String?),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }

  static KeyRequestStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return KeyRequestStatus.approved;
      case 'rejected':
        return KeyRequestStatus.rejected;
      default:
        return KeyRequestStatus.pending;
    }
  }

  String get statusString {
    switch (status) {
      case KeyRequestStatus.approved:
        return 'approved';
      case KeyRequestStatus.rejected:
        return 'rejected';
      case KeyRequestStatus.pending:
        return 'pending';
    }
  }

  @override
  List<Object?> get props => [
        id,
        resellerId,
        quantity,
        justification,
        status,
        rejectionReason,
        createdAt,
        reviewedAt,
      ];
}