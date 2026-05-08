class EMIScheduleModel {
  final String id;
  final String deviceId;
  final int monthNumber;
  final double amount;
  final DateTime dueDate;
  final String status;
  final DateTime? paidAt;
  final String? paymentReference;

  EMIScheduleModel({
    required this.id,
    required this.deviceId,
    required this.monthNumber,
    required this.amount,
    required this.dueDate,
    required this.status,
    this.paidAt,
    this.paymentReference,
  });

  factory EMIScheduleModel.fromJson(Map<String, dynamic> json) {
    return EMIScheduleModel(
      id: json['id'] ?? '',
      deviceId: json['device_id'] ?? '',
      monthNumber: json['month_number'] ?? 0,
      amount: double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      status: json['status'] ?? 'pending',
      paidAt: json['paid_at'] != null
          ? DateTime.tryParse(json['paid_at'].toString())
          : null,
      paymentReference: json['payment_reference'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'month_number': monthNumber,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'status': status,
    };
  }

  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';
}
