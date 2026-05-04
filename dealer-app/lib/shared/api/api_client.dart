import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_certificate_pinning/http_certificate_pinning.dart';
import '../config/env_config.dart';

class ApiClient {
  late Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  ApiClient() {
    dio = Dio(BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      connectTimeout: EnvConfig.connectTimeout,
      receiveTimeout: EnvConfig.receiveTimeout,
      sendTimeout: EnvConfig.sendTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401 && !_isRefreshing) {
          _isRefreshing = true;
          try {
            final refreshed = await _refreshToken();
            if (refreshed) {
              _isRefreshing = false;
              final options = e.requestOptions;
              final token = await _storage.read(key: 'access_token');
              options.headers['Authorization'] = 'Bearer $token';
              final response = await dio.fetch(options);
              return handler.resolve(response);
            }
          } catch (err) {
            _isRefreshing = false;
          }
        }
        return handler.next(e);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) return false;

    try {
      final response = await dio.post('/auth/refresh', data: {
        'refresh_token': refreshToken,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await setTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt: DateTime.parse(data['expires_at']),
        );
        return true;
      }
    } catch (e) {
      await clearTokens();
    }
    return false;
  }

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    await _storage.write(key: 'expires_at', value: expiresAt.toIso8601String());
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'expires_at');
  }

  Future<bool> verifyCertificate() async {
    if (EnvConfig.shouldDisableCertificatePinning) {
      return true;
    }

    try {
      final hashes = EnvConfig.pinnedSpkiHashes;
      if (hashes.isEmpty) return true;

      await HttpCertificatePinning.check(
        serverURL: EnvConfig.apiBaseUrl,
        sha: SHA.SHA256,
        allowedSHAFingerprints: hashes,
        timeout: 10,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.post(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> put(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.put(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> delete(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.delete(path, data: data, queryParameters: queryParameters);
  }
}
