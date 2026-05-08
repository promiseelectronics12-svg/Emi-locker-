import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  static FCMService? _instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Function(Map<String, dynamic>)? onMessageReceived;
  Function(String?)? onTokenRefreshed;

  FCMService._internal();

  factory FCMService() {
    _instance ??= FCMService._internal();
    return _instance!;
  }

  Future<void> initialize() async {
    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await _setupMessageHandlers();
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        await _setupMessageHandlers();
      }
    } else {
      await _setupMessageHandlers();
    }

    final token = await getToken();
    debugPrint('FCM Token: $token');
  }

  Future<void> _setupMessageHandlers() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.messageId}');
      _handleMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Message opened app: ${message.messageId}');
      _handleMessage(message);
    });

    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('Initial message: ${initialMessage.messageId}');
      _handleMessage(initialMessage);
    }
  }

  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    if (data.isNotEmpty) {
      onMessageReceived?.call(Map<String, dynamic>.from(data));
    }

    if (message.notification != null) {
      debugPrint('Notification: ${message.notification?.title} - ${message.notification?.body}');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('Background message: ${message.messageId}');
  }

  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }

  void setOnTokenRefresh(Function(String?) callback) {
    onTokenRefreshed = callback;
    _messaging.onTokenRefresh.listen((token) {
      callback(token);
    });
  }
}