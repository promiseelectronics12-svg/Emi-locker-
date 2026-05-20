import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// Top-level handler required by FCM for background messages.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages handled here.
  // Firebase.initializeApp() is called in main() before this runs.
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  String? _token;
  String? get token => _token;

  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (Android 13+)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: false,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Fetch token
    _token = await FirebaseMessaging.instance.getToken();
    debugPrint('[FCM] Token: $_token');

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _token = newToken;
      debugPrint('[FCM] Token refreshed: $newToken');
      // TODO: POST new token to backend /api/v1/customer/fcm-token
    });

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
      // TODO: show in-app notification banner
    });
  }

  /// POST token to backend. Call after user authenticates.
  /// Endpoint: POST /api/v1/customer/fcm-token
  /// Body: { "token": "fcm_token" }
  /// Status: BACKEND ENDPOINT NOT YET IMPLEMENTED
  Future<void> registerTokenWithBackend(String authToken) async {
    if (_token == null) return;
    // TODO: implement when backend endpoint is ready
    debugPrint('[FCM] registerTokenWithBackend: stub — endpoint not implemented');
  }
}
