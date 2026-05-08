import 'package:equatable/equatable.dart';

class CustomerDetails extends Equatable {
  final String fullName;
  final String nidNumber;
  final String? nidPhotoPath;
  final String phoneNumber;

  const CustomerDetails({
    required this.fullName,
    required this.nidNumber,
    this.nidPhotoPath,
    required this.phoneNumber,
  });

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'nid_number': nidNumber,
    'nid_photo_path': nidPhotoPath,
    'phone_number': phoneNumber,
  };

  @override
  List<Object?> get props => [fullName, nidNumber, nidPhotoPath, phoneNumber];
}

class DeviceInfo extends Equatable {
  final String imei;
  final String? brand;
  final String? model;
  final String? activationKeyId;

  const DeviceInfo({
    required this.imei,
    this.brand,
    this.model,
    this.activationKeyId,
  });

  Map<String, dynamic> toJson() => {
    'imei': imei,
    'brand': brand,
    'model': model,
    'activation_key_id': activationKeyId,
  };

  @override
  List<Object?> get props => [imei, brand, model, activationKeyId];
}

class EMISchedule extends Equatable {
  final double totalPrice;
  final double downPayment;
  final double monthlyInstallment;
  final int durationMonths;
  final DateTime startDate;
  final int graceDays;

  const EMISchedule({
    required this.totalPrice,
    required this.downPayment,
    required this.monthlyInstallment,
    required this.durationMonths,
    required this.startDate,
    this.graceDays = 3,
  });

  double get principal => totalPrice - downPayment;
  double get totalPayable =>
      downPayment + (monthlyInstallment * durationMonths);
  double get totalInterest => totalPayable - totalPrice;

  Map<String, dynamic> toJson() => {
    'total_price': totalPrice,
    'down_payment': downPayment,
    'monthly_installment': monthlyInstallment,
    'duration_months': durationMonths,
    'start_date': startDate.toIso8601String(),
    'grace_days': graceDays,
  };

  @override
  List<Object?> get props => [
    totalPrice,
    downPayment,
    monthlyInstallment,
    durationMonths,
    startDate,
    graceDays,
  ];
}

class EnrollmentSession extends Equatable {
  final CustomerDetails? customer;
  final DeviceInfo? device;
  final EMISchedule? emiSchedule;
  final String? enrollmentToken;
  final String? deviceId;
  final String status;
  final DateTime? consentSignedAt;
  final String? customerSignature;
  final String? dealerSignature;

  const EnrollmentSession({
    this.customer,
    this.device,
    this.emiSchedule,
    this.enrollmentToken,
    this.deviceId,
    this.status = 'pending',
    this.consentSignedAt,
    this.customerSignature,
    this.dealerSignature,
  });

  EnrollmentSession copyWith({
    CustomerDetails? customer,
    DeviceInfo? device,
    EMISchedule? emiSchedule,
    String? enrollmentToken,
    String? deviceId,
    String? status,
    DateTime? consentSignedAt,
    String? customerSignature,
    String? dealerSignature,
  }) {
    return EnrollmentSession(
      customer: customer ?? this.customer,
      device: device ?? this.device,
      emiSchedule: emiSchedule ?? this.emiSchedule,
      enrollmentToken: enrollmentToken ?? this.enrollmentToken,
      deviceId: deviceId ?? this.deviceId,
      status: status ?? this.status,
      consentSignedAt: consentSignedAt ?? this.consentSignedAt,
      customerSignature: customerSignature ?? this.customerSignature,
      dealerSignature: dealerSignature ?? this.dealerSignature,
    );
  }

  @override
  List<Object?> get props => [
    customer,
    device,
    emiSchedule,
    enrollmentToken,
    deviceId,
    status,
    consentSignedAt,
    customerSignature,
    dealerSignature,
  ];
}
