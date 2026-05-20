import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

const String _kBaseUrl = 'https://emi-locker-erkt.onrender.com';

class DeviceInfo {
  final String id;
  final String imei;
  final String? brand;
  final String? model;
  final String? name;
  final String status;
  final String? lockLevel;
  final DateTime? lockedAt;

  const DeviceInfo({
    required this.id,
    required this.imei,
    this.brand,
    this.model,
    this.name,
    required this.status,
    this.lockLevel,
    this.lockedAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        imei: j['imei'] as String,
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        name: j['name'] as String?,
        status: j['status'] as String? ?? 'unknown',
        lockLevel: j['lockLevel'] as String?,
        lockedAt: j['lockedAt'] != null ? DateTime.tryParse(j['lockedAt'] as String) : null,
      );
}

class ScheduleSummary {
  final String id;
  final double totalAmount;
  final double emiAmount;
  final int duration;
  final String scheduleStatus;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? deviceBrand;
  final String? deviceModel;
  final String? lockLevel;
  final List<Map<String, dynamic>> installments;
  final int overdueCount;
  final DateTime? oldestOverdueDate;

  const ScheduleSummary({
    required this.id,
    required this.totalAmount,
    required this.emiAmount,
    required this.duration,
    required this.scheduleStatus,
    this.startDate,
    this.endDate,
    this.deviceBrand,
    this.deviceModel,
    this.lockLevel,
    required this.installments,
    required this.overdueCount,
    this.oldestOverdueDate,
  });

  factory ScheduleSummary.fromJson(Map<String, dynamic> j) {
    final device = j['device'] as Map<String, dynamic>? ?? {};
    return ScheduleSummary(
      id: j['id'] as String,
      totalAmount: (j['totalAmount'] as num).toDouble(),
      emiAmount: (j['emiAmount'] as num).toDouble(),
      duration: j['duration'] as int,
      scheduleStatus: j['scheduleStatus'] as String? ?? 'unknown',
      startDate: j['startDate'] != null ? DateTime.tryParse(j['startDate'] as String) : null,
      endDate: j['endDate'] != null ? DateTime.tryParse(j['endDate'] as String) : null,
      deviceBrand: device['brand'] as String?,
      deviceModel: device['model'] as String?,
      lockLevel: device['lockLevel'] as String?,
      installments: (j['installments'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      overdueCount: j['overdueCount'] as int? ?? 0,
      oldestOverdueDate: j['oldestOverdueDate'] != null
          ? DateTime.tryParse(j['oldestOverdueDate'] as String)
          : null,
    );
  }
}

class DeviceService {
  DeviceService._();
  static final DeviceService instance = DeviceService._();

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (AuthService.instance.appToken != null)
          'Authorization': 'Bearer ${AuthService.instance.appToken}',
      };

  Future<DeviceInfo?> fetchDevice(String imei) async {
    try {
      final uri = Uri.parse('$_kBaseUrl/api/v1/customer/devices/$imei');
      final response = await http.get(uri, headers: _authHeaders);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return DeviceInfo.fromJson(body['device'] as Map<String, dynamic>);
      }
      debugPrint('[DeviceService] fetchDevice ${response.statusCode}: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('[DeviceService] fetchDevice error: $e');
      return null;
    }
  }

  Future<ScheduleSummary?> fetchSchedule() async {
    try {
      final uri = Uri.parse('$_kBaseUrl/api/v1/customer/schedule');
      final response = await http.get(uri, headers: _authHeaders);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return ScheduleSummary.fromJson(body['schedule'] as Map<String, dynamic>);
      }
      debugPrint('[DeviceService] fetchSchedule ${response.statusCode}: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('[DeviceService] fetchSchedule error: $e');
      return null;
    }
  }
}
