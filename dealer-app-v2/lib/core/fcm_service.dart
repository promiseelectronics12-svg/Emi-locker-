import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Must be top-level — runs in a separate isolate when app is terminated/background.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await FcmService.showLocalNotification(message);
}

class FcmService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'emi_dealer_alerts';
  static const _channelName = 'EMI Alerts';
  static const _channelDesc =
      'Alerts for device events, SIM changes, and payments';

  static final _tapController =
      StreamController<Map<String, String>>.broadcast();

  /// Fires when dealer taps a notification. Contains {type, device_id}.
  static Stream<Map<String, String>> get onNotificationTap =>
      _tapController.stream;

  /// Call once at app startup, before runApp.
  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    // Foreground messages — app is open.
    FirebaseMessaging.onMessage.listen(showLocalNotification);

    // Dealer tapped notification while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen(_dispatchTap);

    // Dealer tapped notification that launched app from terminated state.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _dispatchTap(initial);
  }

  /// Request permission and return current authorization status.
  static Future<AuthorizationStatus> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus;
  }

  /// Get current FCM token. Returns null on failure (no crash).
  static Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }

  /// Stream that fires whenever the FCM token is rotated by Firebase.
  static Stream<String> get onTokenRefresh =>
      FirebaseMessaging.instance.onTokenRefresh;

  /// Show a local notification for a received FCM message.
  /// Called for foreground messages and from the background isolate handler.
  static Future<void> showLocalNotification(RemoteMessage message) async {
    final data = message.data;
    final notification = message.notification;

    final title = notification?.title ?? _titleForType(data['type']);
    final body = notification?.body ?? data['message'] ?? '';
    final type = data['type'] ?? '';
    final deviceId = data['device_id'] ?? data['deviceId'] ?? '';

    try {
      await _localNotifications.show(
        message.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: '$type:$deviceId',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] showLocalNotification error: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    final parts = payload.split(':');
    _tapController.add({
      'type': parts.isNotEmpty ? parts[0] : '',
      'device_id': parts.length > 1 ? parts[1] : '',
    });
  }

  static void _dispatchTap(RemoteMessage message) {
    _tapController.add({
      'type': message.data['type'] ?? '',
      'device_id': message.data['device_id'] ?? message.data['deviceId'] ?? '',
    });
  }

  static String _titleForType(String? type) {
    switch (type) {
      case 'sim_removed':
        return 'SIM Removed';
      case 'device_locked':
        return 'Device Locked';
      case 'device_unlocked':
        return 'Device Unlocked';
      case 'app_tamper':
        return 'Tamper Detected';
      case 'shutdown_detected':
        return 'Shutdown Detected';
      case 'payment_confirmed':
        return 'Payment Confirmed';
      case 'advance_payment':
        return 'Advance Payment Confirmed';
      case 'app_removed_suspected':
        return 'App Removal Suspected';
      case 'risk_score_threshold':
        return 'Risk Threshold Reached';
      default:
        return 'EMI Alert';
    }
  }
}
