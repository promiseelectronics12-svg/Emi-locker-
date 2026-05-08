import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';

class EnvConfig {
  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      throw StateError('API_BASE_URL environment variable is not set');
    }
    return url;
  }

  static String get qrProvisioningUrl {
    final url = dotenv.env['QR_PROVISIONING_URL'];
    if (url == null || url.isEmpty) {
      return '$apiBaseUrl/provisioning';
    }
    return url;
  }

  static bool get isDevelopment {
    final url = apiBaseUrl;
    return url.contains('localhost') || url.contains('10.0.2.2');
  }

  static bool get isProduction => !isDevelopment;

  static bool get isLocalApi =>
      apiBaseUrl.contains('localhost') || apiBaseUrl.contains('10.0.2.2');

  static bool get shouldDisableCertificatePinning => isDevelopment;

  static Duration get connectTimeout {
    final val = dotenv.env['CONNECT_TIMEOUT'];
    if (val != null) return Duration(milliseconds: int.tryParse(val) ?? 30000);
    return const Duration(seconds: 30);
  }

  static Duration get receiveTimeout {
    final val = dotenv.env['RECEIVE_TIMEOUT'];
    if (val != null) return Duration(milliseconds: int.tryParse(val) ?? 30000);
    return const Duration(seconds: 30);
  }

  static Duration get sendTimeout {
    final val = dotenv.env['SEND_TIMEOUT'];
    if (val != null) return Duration(milliseconds: int.tryParse(val) ?? 30000);
    return const Duration(seconds: 30);
  }

  static List<String> get pinnedSpkiHashes {
    final hashes = dotenv.env['PINNED_SPKI_HASHES'];
    if (hashes == null || hashes.isEmpty) return const [];
    return hashes.split(',').map((e) => e.trim()).toList();
  }

  static void validateAll() {
    apiBaseUrl;
    qrProvisioningUrl;
    isDevelopment;
    isProduction;
    isLocalApi;
    shouldDisableCertificatePinning;
    connectTimeout;
    receiveTimeout;
    sendTimeout;
    pinnedSpkiHashes;
  }
}