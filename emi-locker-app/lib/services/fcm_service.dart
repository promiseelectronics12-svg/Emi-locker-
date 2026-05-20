import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String _kBaseUrl = 'https://emi-locker-erkt.onrender.com';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  String? _token;
  String? get token => _token;

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: false,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    _token = await FirebaseMessaging.instance.getToken();
    debugPrint('[FCM] Token: $_token');

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _token = newToken;
      debugPrint('[FCM] Token refreshed: $newToken');
      // Caller responsible for re-registering after token refresh
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
      // TODO: show in-app notification banner
    });
  }

  /// POST /api/v1/customer/fcm-token
  /// Call after user authenticates successfully.
  Future<void> registerTokenWithBackend(String authToken) async {
    if (_token == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_kBaseUrl/api/v1/customer/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'token': _token}),
      );
      debugPrint('[FCM] registerTokenWithBackend: ${response.statusCode}');
    } catch (e) {
      debugPrint('[FCM] registerTokenWithBackend error: $e');
    }
  }
}
