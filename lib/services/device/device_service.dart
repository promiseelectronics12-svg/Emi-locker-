import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/device/device_model.dart';

class DeviceService {
  final String _baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref('devices');

  Stream<<ListList<<DeviceDeviceModel>> streamDevices() {
    return _dbRef.onValue.map((event) {
      final Map<<dynamicdynamic, dynamic> data = event.snapshot.value as Map<<dynamicdynamic, dynamic>;
      return data.entries.map((e) => _mapToDevice(e.key, e.value)).toList();
    });
  }

  DeviceModel _mapToDevice(String id, Map<<dynamicdynamic, dynamic> map) {
    return DeviceModel(
      id: id,
      imei: map['imei'] ?? '',
      serial: map['serial'] ?? '',
      oem: map['oem'] ?? '',
      model: map['model'] ?? '',
      androidVersion: map['androidVersion'] ?? '',
      enrollmentDate: DateTime.parse(map['enrollmentDate'] ?? DateTime.now().toIso8601String()),
      status: DeviceStatus.values[map['statusIndex'] ?? 0],
      lastStateChange: DateTime.parse(map['lastStateChange'] ?? DateTime.now().toIso8601String()),
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      lastLocationUpdate: DateTime.parse(map['lastLocationUpdate'] ?? DateTime.now().toIso8601String()),
      emiSchedules: [], // Simplified for brevity in service, should map from DB
      paymentHistory: [],
      customer: CustomerInfo(
        name: map['customerName'] ?? '',
        nid: map['customerNid'] ?? '',
        phone: map['customerPhone'] ?? '',
        nidPhotoUrl: map['customerNidPhoto'] ?? '',
      ),
    );
  }

  Future<<boolbool> requestLock(String deviceId, String reasonCode, String note, String totp) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/lock-request'),
      body: {
        'deviceId': deviceId,
        'reasonCode': reasonCode,
        'note': note,
        'totp': totp,
      },
    );
    return response.statusCode == 200;
  }

  Future<<boolbool> requestUnlock(String deviceId, String totp) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/unlock-request'),
      body: {'deviceId': deviceId, 'totp': totp},
    );
    return response.statusCode == 200;
  }

  Future<<boolbool> grantGracePeriod(String deviceId, int days, String totp) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/grace-period'),
      body: {'deviceId': deviceId, 'days': days, 'totp': totp},
    );
    return response.statusCode == 200;
  }

  Future<<boolbool> sendMessage(String deviceId, String message) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/message'),
      body: {'deviceId': deviceId, 'message': message},
    );
    return response.statusCode == 200;
  }

  Future<<boolbool> pullLocation(String deviceId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/pull-location'),
      body: {'deviceId': deviceId},
    );
    return response.statusCode == 200;
  }
}
