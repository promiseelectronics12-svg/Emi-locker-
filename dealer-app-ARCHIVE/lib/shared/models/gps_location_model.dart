import 'package:equatable/equatable.dart';

class GpsLocationModel extends Equatable {
  final String deviceId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? address;
  final double? accuracy;
  final double? altitude;

  const GpsLocationModel({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.address,
    this.accuracy,
    this.altitude,
  });

  factory GpsLocationModel.fromJson(Map<String, dynamic> json) {
    return GpsLocationModel(
      deviceId: json['device_id'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      address: json['address'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'address': address,
      'accuracy': accuracy,
      'altitude': altitude,
    };
  }

  String get googleMapsUrl => 'https://www.google.com/maps?q=$latitude,$longitude';

  @override
  List<Object?> get props => [deviceId, latitude, longitude, timestamp];
}