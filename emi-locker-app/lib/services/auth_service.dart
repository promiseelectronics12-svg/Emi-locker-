import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String _kBaseUrl = 'https://emi-locker-erkt.onrender.com';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _googleSignIn = GoogleSignIn(scopes: ['email', 'openid']);

  String? _appToken;
  // ignore: unused_field — stored for future token-refresh flow
  String? _refreshToken;
  String? _userId;
  String? _userName;
  String? _userEmail;

  String? get appToken => _appToken;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  bool get isAuthenticated => _appToken != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _appToken = prefs.getString('app_token');
    _refreshToken = prefs.getString('refresh_token');
    _userId = prefs.getString('user_id');
    _userName = prefs.getString('user_name');
    _userEmail = prefs.getString('user_email');
  }

  /// Sign in with Google, then exchange ID token for app JWT.
  /// POST /api/v1/customer/auth/google
  /// Body: { "idToken": "google_id_token", "imei"?: "device_imei" }
  /// Response: { "token": "app_jwt", "refreshToken": "...", "userId": "uuid", "name": "...", "email": "..." }
  Future<AuthResult> signInWithGoogle({String? imei}) async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return AuthResult.cancelled();

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return AuthResult.error('Google ID token missing');

      debugPrint('[Auth] Google sign-in OK: ${account.email}');

      final body = <String, dynamic>{'idToken': idToken};
      if (imei != null && imei.isNotEmpty) body['imei'] = imei;

      final response = await http.post(
        Uri.parse('$_kBaseUrl/api/v1/customer/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && json['status'] == 'ok') {
        final token = json['token'] as String;
        final refreshToken = json['refreshToken'] as String? ?? '';
        final userId = json['userId'] as String;
        final name = json['name'] as String? ?? account.displayName ?? '';
        final email = json['email'] as String? ?? account.email;
        await _persist(token, refreshToken, userId, name, email);
        return AuthResult.success(token: token, userId: userId);
      }

      final code = json['code'] as String? ?? 'UNKNOWN';
      final message = json['message'] as String? ?? 'Sign-in failed';
      debugPrint('[Auth] Backend error $code: $message');

      if (code == 'DEVICE_NOT_ENROLLED') {
        return AuthResult.error('Device not enrolled. Contact your dealer.');
      }
      if (code == 'ACCOUNT_NOT_FOUND') {
        return AuthResult.error('Account not found. Provide your device IMEI on first sign-in.');
      }
      return AuthResult.error(message);
    } catch (e) {
      debugPrint('[Auth] signInWithGoogle error: $e');
      return AuthResult.error(e.toString());
    }
  }

  Future<void> _persist(
    String token,
    String refreshToken,
    String userId,
    String name,
    String email,
  ) async {
    _appToken = token;
    _refreshToken = refreshToken;
    _userId = userId;
    _userName = name;
    _userEmail = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_token', token);
    await prefs.setString('refresh_token', refreshToken);
    await prefs.setString('user_id', userId);
    await prefs.setString('user_name', name);
    await prefs.setString('user_email', email);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _appToken = null;
    _refreshToken = null;
    _userId = null;
    _userName = null;
    _userEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_email');
  }
}

class AuthResult {
  final bool success;
  final bool cancelled;
  final String? token;
  final String? userId;
  final String? error;

  const AuthResult._({
    required this.success,
    required this.cancelled,
    this.token,
    this.userId,
    this.error,
  });

  factory AuthResult.success({required String token, required String userId}) =>
      AuthResult._(success: true, cancelled: false, token: token, userId: userId);

  factory AuthResult.cancelled() =>
      AuthResult._(success: false, cancelled: true);

  factory AuthResult.error(String message) =>
      AuthResult._(success: false, cancelled: false, error: message);
}
