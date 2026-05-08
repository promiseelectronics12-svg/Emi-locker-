import '../api/api_client.dart';
import '../models/device.dart';

class DeviceRepository {
  final ApiClient _apiClient;

  DeviceRepository(this._apiClient);

  Future<List<Device>> getDevices({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/devices',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> devicesJson = data['devices'] as List<dynamic>;
      return devicesJson
          .map((json) => Device.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<Device> getDevice(String deviceId) async {
    try {
      final response = await _apiClient.get('/devices/$deviceId');
      return Device.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<Device> enrollDevice({
    required String customerName,
    required String customerPhone,
    required String customerNid,
    required DateTime customerDob,
    required String activationKey,
    String? imei1,
    String? imei2,
    String? macAddress,
    required double emiAmount,
    required int totalInstallments,
    Map<String, dynamic>? location,
  }) async {
    try {
      final response = await _apiClient.post(
        '/devices/enroll',
        data: {
          'customer_name': customerName,
          'customer_phone': customerPhone,
          'customer_nid': customerNid,
          'customer_dob': customerDob.toIso8601String(),
          'activation_key': activationKey,
          if (imei1 != null) 'imei1': imei1,
          if (imei2 != null) 'imei2': imei2,
          if (macAddress != null) 'mac_address': macAddress,
          'emi_amount': emiAmount,
          'total_installments': totalInstallments,
          if (location != null) 'location': location,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return Device.fromJson(data['device'] as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> verifyNid({
    required String nidNumber,
    required String customerName,
    required DateTime dob,
  }) async {
    try {
      final response = await _apiClient.post(
        '/devices/verify-nid',
        data: {
          'nid_number': nidNumber,
          'customer_name': customerName,
          'dob': dob.toIso8601String(),
        },
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<void> updateDeviceLocation({
    required String deviceId,
    required Map<String, dynamic> location,
  }) async {
    try {
      await _apiClient.put(
        '/devices/$deviceId/location',
        data: {'location': location},
      );
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<void> requestDecouple({
    required String deviceId,
    String? reason,
  }) async {
    try {
      await _apiClient.post(
        '/devices/$deviceId/request-decouple',
        data: {
          if (reason != null) 'reason': reason,
        },
      );
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }
}