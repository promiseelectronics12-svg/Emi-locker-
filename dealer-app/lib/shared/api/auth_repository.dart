import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/user.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _userKey = 'current_user';

  AuthRepository(this._apiClient);

  Future<User> login({
    required String phone,
    required String password,
    String? twoFactorCode,
  }) async {
    try {
      final response = await _apiClient.post(
        '/auth/login',
        data: {
          'phone': phone,
          'password': password,
          if (twoFactorCode != null) 'two_factor_code': twoFactorCode,
        },
      );

      final data = response.data as Map<String, dynamic>;
      await _apiClient.setTokens(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        expiresAt: DateTime.parse(data['expires_at'] as String),
      );

      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.write(key: _userKey, value: user.id);

      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } catch (e) {
    } finally {
      await _apiClient.clearTokens();
      await _storage.delete(key: _userKey);
    }
  }

  Future<User?> getCurrentUser() async {
    try {
      final userId = await _storage.read(key: _userKey);
      if (userId == null) return null;

      final response = await _apiClient.get('/auth/me');
      return User.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      await _storage.delete(key: _userKey);
      return null;
    }
  }
}
