import 'package:equatable/equatable.dart';

enum DealerApplicationStatus { pending, active, suspended, rejected }

class DealerApplication extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String shopName;
  final String tradeLicense;
  final String address;
  final String resellerId;
  final DealerApplicationStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  const DealerApplication({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.shopName,
    required this.tradeLicense,
    required this.address,
    required this.resellerId,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.reviewedAt,
  });

  factory DealerApplication.fromJson(Map<String, dynamic> json) {
    return DealerApplication(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      shopName: json['shop_name'] as String,
      tradeLicense: json['trade_license'] as String,
      address: json['address'] as String,
      resellerId: json['reseller_id'] as String,
      status: _parseStatus(json['status'] as String?),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
    );
  }

  static DealerApplicationStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return DealerApplicationStatus.active;
      case 'suspended':
        return DealerApplicationStatus.suspended;
      case 'rejected':
        return DealerApplicationStatus.rejected;
      default:
        return DealerApplicationStatus.pending;
    }
  }

  String get statusString {
    switch (status) {
      case DealerApplicationStatus.active:
        return 'active';
      case DealerApplicationStatus.suspended:
        return 'suspended';
      case DealerApplicationStatus.rejected:
        return 'rejected';
      case DealerApplicationStatus.pending:
        return 'pending';
    }
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phone,
        shopName,
        tradeLicense,
        address,
        resellerId,
        status,
        rejectionReason,
        createdAt,
        reviewedAt,
      ];
}