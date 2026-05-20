import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

const String _kBaseUrl = 'https://emi-locker-erkt.onrender.com';

enum FetchStatus { ok, unauthorized, noData, networkError }

class FetchResult<T> {
  final FetchStatus status;
  final T? data;
  final String? errorCode;

  const FetchResult({required this.status, this.data, this.errorCode});

  bool get isOk => status == FetchStatus.ok;
  bool get isUnauthorized => status == FetchStatus.unauthorized;
}

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

  Map<String, String> _authHeaders() => {
        'Content-Type': 'application/json',
        if (AuthService.instance.appToken != null)
          'Authorization': 'Bearer ${AuthService.instance.appToken}',
      };

  /// Execute [call] with automatic one-time token refresh on 401.
  /// Returns null on network error; FetchResult.unauthorized if refresh also fails.
  Future<FetchResult<T>> _withTokenRefresh<T>(
    Future<http.Response> Function(Map<String, String> headers) call,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      var response = await call(_authHeaders());

      if (response.statusCode == 401) {
        debugPrint('[DeviceService] 401 — attempting token refresh');
        final refreshed = await AuthService.instance.refreshTokens();
        if (!refreshed) {
          return FetchResult(status: FetchStatus.unauthorized, errorCode: 'TOKEN_EXPIRED');
        }
        response = await call(_authHeaders());
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return FetchResult(status: FetchStatus.ok, data: parse(body));
      }

      final body = _tryParseBody(response.body);
      final code = body?['code'] as String? ?? 'UNKNOWN';
      debugPrint('[DeviceService] ${response.statusCode} $code');

      if (response.statusCode == 401) {
        return FetchResult(status: FetchStatus.unauthorized, errorCode: code);
      }
      return FetchResult(status: FetchStatus.noData, errorCode: code);
    } on http.ClientException catch (e) {
      debugPrint('[DeviceService] Network error: $e');
      return FetchResult(status: FetchStatus.networkError, errorCode: 'NETWORK_ERROR');
    } catch (e) {
      debugPrint('[DeviceService] Unexpected error: $e');
      return FetchResult(status: FetchStatus.networkError, errorCode: 'NETWORK_ERROR');
    }
  }

  Map<String, dynamic>? _tryParseBody(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<FetchResult<DeviceInfo>> fetchDevice(String imei) {
    return _withTokenRefresh(
      (headers) => http.get(
        Uri.parse('$_kBaseUrl/api/v1/customer/devices/$imei'),
        headers: headers,
      ),
      (body) => DeviceInfo.fromJson(body['device'] as Map<String, dynamic>),
    );
  }

  Future<FetchResult<ScheduleSummary>> fetchSchedule() {
    return _withTokenRefresh(
      (headers) => http.get(
        Uri.parse('$_kBaseUrl/api/v1/customer/schedule'),
        headers: headers,
      ),
      (body) => ScheduleSummary.fromJson(body['schedule'] as Map<String, dynamic>),
    );
  }
}
