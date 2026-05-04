import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import '../../models/device_management/device_model.dart';

class DeviceManagementService {
  static final DeviceManagementService _instance = DeviceManagementService._internal();
  factory DeviceManagementService() => _instance;
  DeviceManagementService._internal();

  String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

  Stream<List<DeviceModel>> streamDevices() {
    final ref = FirebaseDatabase.instance.ref('devices');
    return ref.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      return data.values.map((v) => DeviceModel.fromJson(Map<String, dynamic>.from(v))).toList();
    });
  }

  Future<Map<String, dynamic>> getDeviceSummary() async {
    final response = await http.get(Uri.parse('$baseUrl/devices/summary'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to fetch summary');
  }

  Future<bool> requestLock({
    required String deviceId,
    required String reasonCode,
    required String note,
    required String totpCode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/devices/lock-request'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'deviceId': deviceId,
        'reasonCode': reasonCode,
        'note': note,
        'totpCode': totpCode,
      }),
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return body['status'] == 'APPROVED';
    }
    throw Exception(json.decode(response.body)['message'] ?? 'Request failed');
  }

  Future<void> pullLocation(String deviceId) async {
    await http.post(Uri.parse('$baseUrl/devices/$deviceId/pull-location'));
  }

  Future<void> sendDeviceMessage(String deviceId, String message) async {
    await http.post(
      Uri.parse('$baseUrl/devices/$deviceId/message'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'message': message}),
    );
  }

  Future<void> grantGracePeriod(String deviceId, int days) async {
    await http.post(
      Uri.parse('$baseUrl/devices/$deviceId/grace-period'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'days': days}),
    );
  }
}
