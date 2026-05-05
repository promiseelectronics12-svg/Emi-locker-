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
        final token = await _storage.read(key: 'accessToken');
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
              final token = await _storage.read(key: 'accessToken');
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
    final refreshToken = await _storage.read(key: 'refreshToken');
    if (refreshToken == null) return false;

    try {
      final response = await dio.post('/api/v1/auth/refresh', data: {
        'refreshToken': refreshToken,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await setTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
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
  }) async {
    await _storage.write(key: 'accessToken', value: accessToken);
    await _storage.write(key: 'refreshToken', value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'refreshToken');
  }

  Future<String?> getAccessToken() => _storage.read(key: 'accessToken');

  String _normalizePath(String path) {
    if (path.startsWith('/api/v1/')) return path;
    if (path.startsWith('/api/')) return path.replaceFirst('/api/', '/api/v1/');
    if (path.startsWith('/')) return '/api/v1$path';
    return '/api/v1/$path';
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
    return dio.get(_normalizePath(path), queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.post(_normalizePath(path), data: data, queryParameters: queryParameters);
  }

  Future<Response> put(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.put(_normalizePath(path), data: data, queryParameters: queryParameters);
  }

  Future<Response> delete(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return dio.delete(_normalizePath(path), data: data, queryParameters: queryParameters);
  }
}
