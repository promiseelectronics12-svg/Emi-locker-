class EnrollmentModel {
  final String id;
  final String deviceId;
  final String customerName;
  final String customerNid;
  final String customerPhone;
  final String imei;
  final String? activationKeyId;
  final double monthlyAmount;
  final int totalMonths;
  final DateTime? consentSignedAt;
  final String status;

  EnrollmentModel({
    required this.id,
    required this.deviceId,
    required this.customerName,
    required this.customerNid,
    required this.customerPhone,
    required this.imei,
    this.activationKeyId,
    required this.monthlyAmount,
    required this.totalMonths,
    this.consentSignedAt,
    required this.status,
  });

  factory EnrollmentModel.fromJson(Map<String, dynamic> json) {
    return EnrollmentModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      customerName: json['customer_name'] ?? '',
      customerNid: json['customer_nid'] ?? '',
      customerPhone: json['customer_phone'] ?? '',
      imei: json['imei'] ?? '',
      activationKeyId: json['activation_key_id'],
      monthlyAmount: double.tryParse(json['monthly_amount'].toString()) ?? 0,
      totalMonths: json['total_months'] ?? 0,
      consentSignedAt: json['consent_signed_at'] != null
          ? DateTime.tryParse(json['consent_signed_at'].toString())
          : null,
      status: json['status'] ?? 'pending',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'customer_name': customerName,
      'customer_nid': customerNid,
      'customer_phone': customerPhone,
      'imei': imei,
      'activation_key_id': activationKeyId,
      'monthly_amount': monthlyAmount,
      'total_months': totalMonths,
      'status': status,
    };
  }
}
