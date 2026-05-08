import 'package:equatable/equatable.dart';

class DeviceRepository {
  Future<List<DeviceModel>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 100));
    return [];
  }

  Future<DeviceModel?> getDeviceById(String id) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return null;
  }

  Future<bool> enrollDevice(DeviceModel device) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return true;
  }
}

class DeviceModel {
  final String? id;
  final String? imei;
  final String? status;
  final String? dealerId;
  final DateTime? createdAt;

  const DeviceModel({
    this.id,
    this.imei,
    this.status,
    this.dealerId,
    this.createdAt,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'],
      imei: json['imei'],
      status: json['status'],
      dealerId: json['dealerId'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imei': imei,
      'status': status,
      'dealerId': dealerId,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}