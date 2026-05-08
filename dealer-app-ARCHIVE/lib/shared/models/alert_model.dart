import 'package:equatable/equatable.dart';

enum AlertType {
  fraudAlert,
  anomalyDetection,
  adminMessage,
  paymentReminder,
  lockStatusChange,
}

enum AlertSeverity {
  low,
  medium,
  high,
  critical,
}

extension AlertTypeExtension on AlertType {
  String get displayName {
    switch (this) {
      case AlertType.fraudAlert:
        return 'Fraud Alert';
      case AlertType.anomalyDetection:
        return 'Anomaly Detected';
      case AlertType.adminMessage:
        return 'Admin Message';
      case AlertType.paymentReminder:
        return 'Payment Reminder';
      case AlertType.lockStatusChange:
        return 'Lock Status Change';
    }
  }

  static AlertType fromString(String? type) {
    switch (type?.toUpperCase()) {
      case 'FRAUD_ALERT':
        return AlertType.fraudAlert;
      case 'ANOMALY_DETECTION':
        return AlertType.anomalyDetection;
      case 'ADMIN_MESSAGE':
        return AlertType.adminMessage;
      case 'PAYMENT_REMINDER':
        return AlertType.paymentReminder;
      case 'LOCK_STATUS_CHANGE':
        return AlertType.lockStatusChange;
      default:
        return AlertType.adminMessage;
    }
  }
}

extension AlertSeverityExtension on AlertSeverity {
  String get displayName {
    switch (this) {
      case AlertSeverity.low:
        return 'Low';
      case AlertSeverity.medium:
        return 'Medium';
      case AlertSeverity.high:
        return 'High';
      case AlertSeverity.critical:
        return 'Critical';
    }
  }

  static AlertSeverity fromString(String? severity) {
    switch (severity?.toUpperCase()) {
      case 'LOW':
        return AlertSeverity.low;
      case 'MEDIUM':
        return AlertSeverity.medium;
      case 'HIGH':
        return AlertSeverity.high;
      case 'CRITICAL':
        return AlertSeverity.critical;
      default:
        return AlertSeverity.low;
    }
  }
}

class AlertModel extends Equatable {
  final String id;
  final String deviceId;
  final AlertType type;
  final AlertSeverity severity;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? metadata;

  const AlertModel({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    required this.createdAt,
    this.isRead = false,
    this.metadata,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    return AlertModel(
      id: json['id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      type: AlertTypeExtension.fromString(json['type'] as String?),
      severity: AlertSeverityExtension.fromString(json['severity'] as String?),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'type': type.name.toUpperCase(),
      'severity': severity.name.toUpperCase(),
      'title': title,
      'message': message,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'metadata': metadata,
    };
  }

  AlertModel copyWith({
    String? id,
    String? deviceId,
    AlertType? type,
    AlertSeverity? severity,
    String? title,
    String? message,
    DateTime? createdAt,
    bool? isRead,
    Map<String, dynamic>? metadata,
  }) {
    return AlertModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [id, deviceId, type, createdAt];
}