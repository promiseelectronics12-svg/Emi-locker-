import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/dealer_application.dart';
import '../models/reseller_stats.dart';
import '../models/key_request.dart';
import '../models/dealer_performance.dart';
import '../models/dealer.dart';

class ResellerRepository {
  final ApiClient _apiClient;

  ResellerRepository(this._apiClient);

  Future<ResellerStats> getResellerStats() async {
    try {
      final response = await _apiClient.get('/api/v1/reseller/stats');
      return ResellerStats.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<DealerApplication>> getDealerApplications({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/reseller/dealers/applications',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> applications =
          data['applications'] as List<dynamic>? ?? [];
      return applications
          .map((json) =>
              DealerApplication.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Dealer>> getDealers({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/reseller/dealers',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> dealers = data['dealers'] as List<dynamic>? ?? [];
      return dealers.map((json) => Dealer.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<DealerApplication> getDealerApplicationDetails(
      String applicationId) async {
    try {
      final response = await _apiClient
          .get('/api/v1/reseller/dealers/applications/$applicationId');
      return DealerApplication.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Dealer> getDealerDetails(String dealerId) async {
    try {
      final response =
          await _apiClient.get('/api/v1/reseller/dealers/$dealerId');
      return Dealer.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<DealerPerformance> getDealerPerformance(String dealerId) async {
    try {
      final response =
          await _apiClient.get('/api/v1/reseller/dealers/$dealerId/performance');
      return DealerPerformance.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> approveDealer(String applicationId) async {
    try {
      await _apiClient.post(
        '/api/v1/reseller/dealers/applications/$applicationId/approve',
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> rejectDealer({
    required String applicationId,
    required String reason,
  }) async {
    try {
      await _apiClient.post(
        '/api/v1/reseller/dealers/applications/$applicationId/reject',
        data: {'reason': reason},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> suspendDealer(String dealerId) async {
    try {
      await _apiClient.post('/api/v1/reseller/dealers/$dealerId/suspend');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> reactivateDealer(String dealerId) async {
    try {
      await _apiClient.post('/api/v1/reseller/dealers/$dealerId/reactivate');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> assignKeysToDealer({
    required String dealerId,
    required int quantity,
    required String twoFactorCode,
  }) async {
    try {
      await _apiClient.post(
        '/api/v1/reseller/dealers/$dealerId/assign-keys',
        data: {
          'quantity': quantity,
          'two_factor_code': twoFactorCode,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<KeyRequest> requestKeys({
    required int quantity,
    required String justification,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/reseller/keys/request',
        data: {
          'quantity': quantity,
          'justification': justification,
        },
      );
      return KeyRequest.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<KeyRequest>> getKeyRequests({
    String? status,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/v1/reseller/keys/requests',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> requests = data['requests'] as List<dynamic>? ?? [];
      return requests
          .map((json) => KeyRequest.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<KeyRequest> getKeyRequestDetails(String requestId) async {
    try {
      final response =
          await _apiClient.get('/api/v1/reseller/keys/requests/$requestId');
      return KeyRequest.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, int>> getKeyInventory() async {
    try {
      final response = await _apiClient.get('/api/v1/reseller/keys/inventory');
      final data = response.data as Map<String, dynamic>;
      return {
        'total': data['total'] as int? ?? 0,
        'available': data['available'] as int? ?? 0,
        'assigned': data['assigned'] as int? ?? 0,
        'used': data['used'] as int? ?? 0,
      };
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<int> getMonthlyQuota() async {
    try {
      final response = await _apiClient.get('/api/v1/reseller/quota');
      final data = response.data as Map<String, dynamic>;
      return data['monthly_quota'] as int? ?? 0;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<bool> canRequestKeys(int requestedQuantity, int monthlyQuota) async {
    final stats = await getResellerStats();
    final maxPerRequest = (monthlyQuota * 0.20).floor();
    final remainingQuota = stats.remainingQuota;

    if (requestedQuantity > maxPerRequest) {
      return false;
    }
    if (requestedQuantity > remainingQuota) {
      return false;
    }
    return true;
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      final data = e.response!.data;
      if (data is Map<String, dynamic> && data.containsKey('message')) {
        return data['message'] as String;
      }
      switch (e.response!.statusCode) {
        case 400:
          return 'Invalid request. Please check your input.';
        case 401:
          return 'Session expired. Please login again.';
        case 403:
          return 'You do not have permission to perform this action.';
        case 404:
          return 'Resource not found.';
        case 422:
          return 'Validation error. Please check your input.';
        case 429:
          return 'Too many requests. Please try again later.';
        default:
          return 'An error occurred. Please try again.';
      }
    }
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout. Please check your internet connection.';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Server took too long to respond. Please try again.';
    }
    return 'Network error. Please check your connection.';
  }
}