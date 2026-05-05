import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import '../models/user.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _userKey = 'current_user';
  static const String _tempTokenKey = 'tempToken';

  AuthRepository(this._apiClient);

  Future<User> login({
    required String phone,
    required String password,
    String? twoFactorCode,
  }) async {
    try {
      Map<String, dynamic> data;

      if (twoFactorCode == null) {
        final response = await _apiClient.post(
          '/api/v1/auth/login',
          data: {
            'email': phone,
            'password': password,
          },
        );

        data = response.data as Map<String, dynamic>;
        final tempToken = data['tempToken'] as String?;
        if (tempToken == null) {
          throw Exception('TEMP_TOKEN_MISSING');
        }
        await _storage.write(key: _tempTokenKey, value: tempToken);

        if (data['requires2FA'] == true) {
          throw Exception('2FA_REQUIRED');
        }
      }

      final tempToken = await _storage.read(key: _tempTokenKey);
      final verifyResponse = await _apiClient.post(
        '/api/v1/auth/2fa/verify',
        data: {
          'tempToken': tempToken,
          if (twoFactorCode != null) 'code': twoFactorCode,
        },
      );

      data = verifyResponse.data as Map<String, dynamic>;
      await _apiClient.setTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      await _storage.delete(key: _tempTokenKey);

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
      // Logout must clear local tokens even when the server session is already gone.
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
