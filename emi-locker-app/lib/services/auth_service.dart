// ignore: unused_import — dart:convert + http needed when backend endpoint is wired
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
// ignore: unused_import
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ignore: unused_element — used when backend auth endpoint is implemented
const String _kBaseUrl = 'https://emi-locker-erkt.onrender.com';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final _googleSignIn = GoogleSignIn(scopes: ['email', 'openid']);

  String? _appToken;
  String? _userId;
  String? get appToken => _appToken;
  String? get userId => _userId;
  bool get isAuthenticated => _appToken != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _appToken = prefs.getString('app_token');
    _userId = prefs.getString('user_id');
  }

  /// Sign in with Google, then exchange ID token for app JWT.
  /// Backend endpoint: POST /api/v1/customer/auth/google
  /// Body: { "idToken": "google_id_token", "imei": "device_imei" }
  /// Response: { "token": "app_jwt", "userId": "uuid" }
  /// Status: BACKEND ENDPOINT NOT YET IMPLEMENTED
  Future<AuthResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return AuthResult.cancelled();

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return AuthResult.error('Google ID token missing');

      debugPrint('[Auth] Google sign-in OK: ${account.email}');

      // TODO: exchange idToken with backend when endpoint is ready
      // Stub: persist dummy token for UI flow testing
      const stubToken = 'stub_token_replace_when_backend_ready';
      const stubUserId = 'stub_user_id';
      await _persist(stubToken, stubUserId);

      return AuthResult.success(token: stubToken, userId: stubUserId);
    } catch (e) {
      debugPrint('[Auth] signInWithGoogle error: $e');
      return AuthResult.error(e.toString());
    }
  }

  Future<void> _persist(String token, String userId) async {
    _appToken = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_token', token);
    await prefs.setString('user_id', userId);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _appToken = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_token');
    await prefs.remove('user_id');
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
