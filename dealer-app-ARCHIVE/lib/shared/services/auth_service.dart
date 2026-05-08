import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _userKey = 'current_user';
  static const String _tempTokenKey = 'tempToken';

  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<User?> getCurrentUser() async {
    final userData = await _storage.read(key: _userKey);
    if (userData == null) return null;

    try {
      final Map<String, dynamic> json =
          Map<String, dynamic>.from(Uri.splitQueryString(userData));
      return User.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveUser(User user) async {
    final params = user.toJson().entries.map((e) => '${e.key}=${e.value}').join('&');
    await _storage.write(key: _userKey, value: params);
  }

  Future<void> clearUser() async {
    await _storage.delete(key: _userKey);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final tempToken = data['tempToken'] as String?;
    if (tempToken == null) {
      return data;
    }
    await _storage.write(key: _tempTokenKey, value: tempToken);

    if (data['requires2FA'] == true) {
      return data;
    }

    final verifyResponse = await _apiClient.post(
      '/api/v1/auth/2fa/verify',
      data: {'tempToken': tempToken},
    );
    final verifiedData = verifyResponse.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      accessToken: verifiedData['accessToken'] as String,
      refreshToken: verifiedData['refreshToken'] as String,
    );

    final user = User.fromJson(verifiedData['user'] as Map<String, dynamic>);
    await saveUser(user);

    return verifiedData;
  }

  Future<Map<String, dynamic>> registerDealer({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String shopName,
    required String tradeLicense,
    required String address,
    required String resellerCode,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/auth/register/dealer',
      data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'shop_name': shopName,
        'trade_license': tradeLicense,
        'address': address,
        'reseller_code': resellerCode,
      },
    );

    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );

    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await saveUser(user);

    return data;
  }

  Future<Map<String, dynamic>> registerReseller({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String companyName,
    required String tradeLicense,
    required String address,
  }) async {
    final response = await _apiClient.post(
      '/api/v1/auth/register/reseller',
      data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'company_name': companyName,
        'trade_license': tradeLicense,
        'address': address,
      },
    );

    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );

    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await saveUser(user);

    return data;
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/api/v1/auth/logout');
    } catch (_) {}
    await _apiClient.clearTokens();
    await clearUser();
  }

  Future<Map<String, dynamic>> setup2FA() async {
    final response = await _apiClient.post('/api/v1/auth/2fa/setup');
    return response.data as Map<String, dynamic>;
  }

  Future<bool> verify2FA(String code) async {
    final tempToken = await _storage.read(key: _tempTokenKey);
    final response = await _apiClient.post(
      '/api/v1/auth/2fa/verify',
      data: {'tempToken': tempToken, 'code': code},
    );
    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    await _storage.delete(key: _tempTokenKey);
    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await saveUser(user);
    return true;
  }

  Future<void> disable2FA(String code) async {
    await _apiClient.post(
      '/api/v1/auth/2fa/disable',
      data: {'code': code},
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.post(
      '/api/v1/users/change-password',
      data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  Future<bool> isLoggedIn() async {
    final token = await _apiClient.getAccessToken();
    return token != null;
  }

  Future<Map<String, dynamic>> refreshTokens() async {
    final refreshToken = await _storage.read(key: 'refreshToken');
    final response = await _apiClient.post(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return data;
  }
}
