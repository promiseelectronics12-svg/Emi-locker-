import '../api/api_client.dart';
import '../models/activation_key.dart';

class KeyRepository {
  final ApiClient _apiClient;

  KeyRepository(this._apiClient);

  Future<List<ActivationKey>> getKeys({
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await _apiClient.get(
        '/keys',
        queryParameters: {
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> keysJson = data['keys'] as List<dynamic>;
      return keysJson
          .map((json) => ActivationKey.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<int> getAvailableKeyCount() async {
    try {
      final response = await _apiClient.get('/keys/count', queryParameters: {
        'status': 'AVAILABLE',
      });
      final data = response.data as Map<String, dynamic>;
      return data['count'] as int;
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<ActivationKey> getKey(String keyId) async {
    try {
      final response = await _apiClient.get('/keys/$keyId');
      return ActivationKey.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }
}