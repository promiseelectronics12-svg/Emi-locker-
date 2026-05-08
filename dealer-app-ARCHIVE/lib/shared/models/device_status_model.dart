class DeviceStatusModel {
  final String deviceId;
  final String status;
  final double? latitude;
  final double? longitude;
  final String? lockMode;
  final DateTime lastUpdate;

  DeviceStatusModel({
    required this.deviceId,
    required this.status,
    this.latitude,
    this.longitude,
    this.lockMode,
    required this.lastUpdate,
  });

  factory DeviceStatusModel.fromJson(Map<String, dynamic> json) {
    return DeviceStatusModel(
      deviceId: json['device_id'] as String,
      status: json['status'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      lockMode: json['lock_mode'] as String?,
      lastUpdate: DateTime.parse(json['last_update'] as String),
    );
  }
}

class NotificationModel {
  final String id;
  final String title;
  final String body;
  final String? type;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  final bool isRead;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.data,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: json['type'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
    );
  }
}

class EmiScheduleModel {
  final int month;
  final int year;
  final double amount;
  final DateTime dueDate;
  final bool isPaid;
  final DateTime? paidDate;
  final double? paidAmount;

  EmiScheduleModel({
    required this.month,
    required this.year,
    required this.amount,
    required this.dueDate,
    required this.isPaid,
    this.paidDate,
    this.paidAmount,
  });

  factory EmiScheduleModel.fromJson(Map<String, dynamic> json) {
    return EmiScheduleModel(
      month: json['month'] as int,
      year: json['year'] as int,
      amount: (json['amount'] as num).toDouble(),
      dueDate: DateTime.parse(json['due_date'] as String),
      isPaid: json['is_paid'] as bool,
      paidDate: json['paid_date'] != null
          ? DateTime.parse(json['paid_date'] as String)
          : null,
      paidAmount: (json['paid_amount'] as num?)?.toDouble(),
    );
  }
}