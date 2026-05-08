import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CommandSigner {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _nonceKey = 'command_nonce';
  static const String _lastTimestampKey = 'command_timestamp';

  static Future<String> sign(String payload) async {
    return await _computeHmac(payload);
  }

  static Future<String> signCommand({
    required String action,
    required String deviceImei,
    String? serial,
    String? nonce,
    String? timestamp,
  }) async {
    final signingNonce = nonce ?? _generateNonce();
    final signingTimestamp = timestamp ?? _generateTimestamp();

    final payload = _buildCanonicalPayload(
      action: action,
      deviceImei: deviceImei,
      serial: serial,
      timestamp: signingTimestamp,
      nonce: signingNonce,
    );

    return await _computeHmac(payload);
  }

  static String _buildCanonicalPayload({
    required String action,
    required String deviceImei,
    String? serial,
    required String timestamp,
    required String nonce,
  }) {
    return '$action|$deviceImei|${serial ?? ''}|$timestamp|$nonce';
  }

  static Future<String> _computeHmac(String payload) async {
    final secret = await _storage.read(key: 'hmac_signing_secret');
    if (secret == null || secret.isEmpty) {
      if (kDebugMode) {
        throw Exception('HMAC secret not configured. Ensure hmac_signing_secret is set in SecureStorage.');
      }
      throw Exception('Signing secret not available in production');
    }

    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  static String _generateNonce() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  static String _generateTimestamp() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  static Future<bool> verifySignature({
    required String signature,
    required String action,
    required String deviceImei,
    String? serial,
    required String timestamp,
    required String nonce,
  }) async {
    try {
      final payload = _buildCanonicalPayload(
        action: action,
        deviceImei: deviceImei,
        serial: serial,
        timestamp: timestamp,
        nonce: nonce,
      );

      final expectedSignature = await _computeHmac(payload);
      
      if (signature != expectedSignature) return false;

      final now = DateTime.now().millisecondsSinceEpoch;
      final timeDiff = (now - int.parse(timestamp)).abs();
      if (timeDiff > 300000) return false; // 5 minute window

      final lastNonce = await _storage.read(key: _nonceKey);
      if (lastNonce == nonce) return false;
      await _storage.write(key: _nonceKey, value: nonce);

      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, String>> buildCommandHeaders({
    required String action,
    required String deviceImei,
    String? serial,
    String? nonce,
    String? timestamp,
  }) async {
    final signingNonce = nonce ?? _generateNonce();
    final signingTimestamp = timestamp ?? _generateTimestamp();
    final signature = await signCommand(
      action: action,
      deviceImei: deviceImei,
      serial: serial,
      nonce: signingNonce,
      timestamp: signingTimestamp,
    );

    return {
      'X-Command-Signature': signature,
      'X-Command-Timestamp': signingTimestamp,
      'X-Command-Nonce': signingNonce,
      'X-Command-IMEI': deviceImei,
      if (serial != null) 'X-Command-Serial': serial,
    };
  }
}
