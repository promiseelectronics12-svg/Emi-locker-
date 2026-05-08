import 'package:dio/dio.dart';
import '../config/env_config.dart';
import '../models/exceptions.dart';
import '../models/device_model.dart';
import '../models/alert_model.dart';
import '../models/emi_schedule_model.dart';
import '../models/payment_model.dart';
import '../models/gps_location_model.dart';

class DeviceManagementService {
  final Dio _dio;

  DeviceManagementService({Dio? dio}) : _dio = dio ?? Dio();

  String get _baseUrl => EnvConfig.apiBaseUrl;

  Future<void> _configureDio() async {
    _dio.options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    );
  }

  Future<List<DeviceModel>> getMyDevices(String dealerId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/dealers/$dealerId/devices');
      final data = response.data as List;
      return data.map((e) => DeviceModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<DeviceModel> getDeviceDetails(String deviceId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/devices/$deviceId');
      return DeviceModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<EMIScheduleModel>> getEmiSchedule(String deviceId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/devices/$deviceId/emi-schedule');
      final data = response.data as List;
      return data.map((e) => EMIScheduleModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<PaymentModel>> getPaymentHistory(String deviceId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/devices/$deviceId/payments');
      final data = response.data as List;
      return data.map((e) => PaymentModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<GpsLocationModel?> getLastKnownLocation(String deviceId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/devices/$deviceId/location');
      if (response.data != null) {
        return GpsLocationModel.fromJson(response.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleDioError(e);
    }
  }

  Future<LockRequestResult> submitLockRequest({
    required String deviceId,
    required String reasonCode,
    required String totpCode,
    String? dealerNote,
  }) async {
    try {
      await _configureDio();
      final response = await _dio.post(
        '/api/v1/devices/$deviceId/lock-request',
        data: {
          'reason_code': reasonCode,
          'totp_code': totpCode,
          'dealer_note': dealerNote,
        },
      );
      return LockRequestResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data != null && data is Map<String, dynamic>) {
          return LockRequestResult(
            approved: false,
            message: data['message'] as String? ?? 'Request rejected',
            rejectionReason: data['rejection_reason'] as String?,
            requestId: data['request_id'] as String?,
          );
        }
      }
      throw _handleDioError(e);
    }
  }

  Future<LockRequestResult> submitUnlockRequest({
    required String deviceId,
    required String totpCode,
    String? reason,
  }) async {
    try {
      await _configureDio();
      final response = await _dio.post(
        '/api/v1/devices/$deviceId/unlock-request',
        data: {
          'totp_code': totpCode,
          'reason': reason,
        },
      );
      return LockRequestResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data != null && data is Map<String, dynamic>) {
          return LockRequestResult(
            approved: false,
            message: data['message'] as String? ?? 'Request rejected',
            rejectionReason: data['rejection_reason'] as String?,
            requestId: data['request_id'] as String?,
          );
        }
      }
      throw _handleDioError(e);
    }
  }

  Future<bool> grantGracePeriod({
    required String deviceId,
    required int days,
    required String totpCode,
    String? reason,
  }) async {
    try {
      await _configureDio();
      await _dio.post(
        '/api/v1/devices/$deviceId/grace-period',
        data: {
          'days': days,
          'totp_code': totpCode,
          'reason': reason,
        },
      );
      return true;
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> sendMessageToDevice({
    required String deviceId,
    required String message,
    required String totpCode,
  }) async {
    try {
      await _configureDio();
      await _dio.post(
        '/api/v1/devices/$deviceId/message',
        data: {
          'message': message,
          'totp_code': totpCode,
        },
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> pullDeviceLocation({
    required String deviceId,
    required String totpCode,
  }) async {
    try {
      await _configureDio();
      await _dio.post(
        '/api/v1/devices/$deviceId/pull-location',
        data: {
          'totp_code': totpCode,
        },
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<List<AlertModel>> getAlerts(String dealerId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/dealers/$dealerId/alerts');
      final data = response.data as List;
      return data.map((e) => AlertModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> markAlertAsRead(String alertId) async {
    try {
      await _configureDio();
      await _dio.patch('/api/v1/alerts/$alertId/read');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<void> markAllAlertsAsRead(String dealerId) async {
    try {
      await _configureDio();
      await _dio.patch('/api/v1/dealers/$dealerId/alerts/read-all');
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Future<DashboardStats> getDashboardStats(String dealerId) async {
    try {
      await _configureDio();
      final response = await _dio.get('/api/v1/dealers/$dealerId/stats');
      return DashboardStats.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  Exception _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(message: 'Connection timeout. Please try again.');
      case DioExceptionType.connectionError:
        return NetworkException(message: 'No internet connection.');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['message'] as String?;
        if (statusCode == 401) {
          return AuthException(message: 'Session expired. Please login again.');
        } else if (statusCode == 403) {
          return AuthException(message: message ?? 'Access denied.');
        } else if (statusCode == 404) {
          return NotFoundException(message: message ?? 'Resource not found.');
        } else if (statusCode == 422) {
          return ValidationException(message: message ?? 'Validation failed.');
        }
        return ApiException(message: message ?? 'An error occurred.');
      default:
        return ApiException(message: 'An unexpected error occurred.');
    }
  }
}

class LockRequestResult {
  final bool approved;
  final String message;
  final String? rejectionReason;
  final String? requestId;

  LockRequestResult({
    required this.approved,
    required this.message,
    this.rejectionReason,
    this.requestId,
  });

  factory LockRequestResult.fromJson(Map<String, dynamic> json) {
    return LockRequestResult(
      approved: json['approved'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      rejectionReason: json['rejection_reason'] as String?,
      requestId: json['request_id'] as String?,
    );
  }
}

class DashboardStats {
  final int totalDevices;
  final int overdueCount;
  final int upcomingEmisThisWeek;
  final double collectionRate;
  final int activeDevices;
  final int lockedDevices;
  final int gracePeriodDevices;

  DashboardStats({
    required this.totalDevices,
    required this.overdueCount,
    required this.upcomingEmisThisWeek,
    required this.collectionRate,
    required this.activeDevices,
    required this.lockedDevices,
    required this.gracePeriodDevices,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalDevices: json['total_devices'] as int? ?? 0,
      overdueCount: json['overdue_count'] as int? ?? 0,
      upcomingEmisThisWeek: json['upcoming_emis_this_week'] as int? ?? 0,
      collectionRate: (json['collection_rate'] as num?)?.toDouble() ?? 0.0,
      activeDevices: json['active_devices'] as int? ?? 0,
      lockedDevices: json['locked_devices'] as int? ?? 0,
      gracePeriodDevices: json['grace_period_devices'] as int? ?? 0,
    );
  }

  factory DashboardStats.empty() {
    return DashboardStats(
      totalDevices: 0,
      overdueCount: 0,
      upcomingEmisThisWeek: 0,
      collectionRate: 0.0,
      activeDevices: 0,
      lockedDevices: 0,
      gracePeriodDevices: 0,
    );
  }
}