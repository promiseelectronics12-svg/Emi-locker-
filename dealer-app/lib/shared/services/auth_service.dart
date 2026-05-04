import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _userKey = 'current_user';

  AuthService({required ApiClient apiClient}) : _apiClient = apiClient;

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
      '/auth/login',
      data: {
        'email': email,
        'password': password,
      },
    );

    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );

    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await saveUser(user);

    return data;
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
      '/auth/register/dealer',
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
      data['access_token'] as String,
      data['refresh_token'] as String,
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
      '/auth/register/reseller',
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
      data['access_token'] as String,
      data['refresh_token'] as String,
    );

    final user = User.fromJson(data['user'] as Map<String, dynamic>);
    await saveUser(user);

    return data;
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/auth/logout');
    } catch (_) {}
    await _apiClient.clearTokens();
    await clearUser();
  }

  Future<Map<String, dynamic>> setup2FA() async {
    final response = await _apiClient.post('/auth/2fa/setup');
    return response.data as Map<String, dynamic>;
  }

  Future<bool> verify2FA(String code) async {
    final response = await _apiClient.post(
      '/auth/2fa/verify',
      data: {'code': code},
    );
    final data = response.data as Map<String, dynamic>;
    return data['success'] as bool;
  }

  Future<void> disable2FA(String code) async {
    await _apiClient.post(
      '/auth/2fa/disable',
      data: {'code': code},
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _apiClient.post(
      '/auth/change-password',
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<bool> isLoggedIn() async {
    final token = await _apiClient.getAccessToken();
    return token != null;
  }

  Future<Map<String, dynamic>> refreshTokens() async {
    final response = await _apiClient.post('/auth/refresh');
    final data = response.data as Map<String, dynamic>;
    await _apiClient.setTokens(
      data['access_token'] as String,
      data['refresh_token'] as String,
    );
    return data;
  }
}