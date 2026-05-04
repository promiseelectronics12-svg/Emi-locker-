import '../api/api_client.dart';
import '../models/lock_request.dart';

class LockRequestRepository {
  final ApiClient _apiClient;

  LockRequestRepository(this._apiClient);

  Future<List<LockRequest>> getLockRequests({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/lock-requests',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> requestsJson = data['requests'] as List<dynamic>;
      return requestsJson
          .map((json) => LockRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<LockRequest> getLockRequest(String requestId) async {
    try {
      final response = await _apiClient.get('/lock-requests/$requestId');
      return LockRequest.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<LockRequest> submitLockRequest({
    required String deviceId,
    required String reasonCode,
    String? dealerNote,
  }) async {
    try {
      final response = await _apiClient.post(
        '/lock-requests',
        data: {
          'device_id': deviceId,
          'reason_code': reasonCode,
          if (dealerNote != null && dealerNote.isNotEmpty)
            'dealer_note': dealerNote,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return LockRequest.fromJson(data['request'] as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<LockRequest> getDeviceLockRequest(String deviceId) async {
    try {
      final response = await _apiClient.get('/devices/$deviceId/lock-request');
      return LockRequest.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }
}