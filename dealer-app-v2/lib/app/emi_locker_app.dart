import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/local_vault.dart';
import '../core/google_vault.dart';
import '../core/sse_service.dart';
import '../screens/dealer/unlock_flow_screen.dart';
import '../screens/dealer/lock_detail_screen.dart';
import '../screens/dealer/device_search_screen.dart';
import '../screens/dealer/customer_credit_screen.dart';
import '../screens/dealer/fraud_center_screen.dart';
import '../screens/dealer/evidence_vault_screen.dart';
import '../screens/dealer/bind_device_wizard.dart';
import '../screens/reseller/credit_summary_screen.dart';
import '../screens/shared/biometric_lock_screen.dart';
import '../screens/shared/google_drive_onboarding_screen.dart';
import '../screens/shared/onboarding_screen.dart';

import 'package:dio/dio.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../core/biometric_service.dart';

const storage = FlutterSecureStorage();
const localApiBaseUrl = 'http://localhost:3000';
const localProvisioningUrl = '$localApiBaseUrl/provisioning';
const dartDefinedApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const dartDefinedProvisioningUrl = String.fromEnvironment(
  'QR_PROVISIONING_URL',
);

String _trimTrailingSlash(String value) {
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

String configuredApiBaseUrl() {
  if (dartDefinedApiBaseUrl.trim().isNotEmpty) {
    return _trimTrailingSlash(dartDefinedApiBaseUrl.trim());
  }
  return _trimTrailingSlash(dotenv.env['API_BASE_URL'] ?? localApiBaseUrl);
}

String configuredProvisioningUrl() {
  if (dartDefinedProvisioningUrl.trim().isNotEmpty) {
    return _trimTrailingSlash(dartDefinedProvisioningUrl.trim());
  }
  if (kDebugMode) return localProvisioningUrl;
  return _trimTrailingSlash(
    dotenv.env['QR_PROVISIONING_URL'] ?? localProvisioningUrl,
  );
}

class AppTone {
  static const brand = Color(0xFF00A86B);
  static const brandDark = Color(0xFF059669);
  static const brandLight = Color(0xFFE6F7F1);
  static const accent = Color(0xFF635BFF);
  static const accentLight = Color(0xFFF0EFFE);
  static const ink = Color(0xFF0D1117);
  static const muted = Color(0xFF6B7280);
  static const subtle = Color(0xFFD1D5DB);
  static const page = Color(0xFFF7F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);
  static const violet = Color(0xFF8B5CF6);

  // Legacy aliases to prevent compile errors before full refactor:
  static const emerald = brand;
  static const emeraldDark = brandDark;
  static const blue = info;
  static const amber = warning;
  static const red = danger;
  static const line = subtle;
}

const _fast = Duration(milliseconds: 160);
const _medium = Duration(milliseconds: 280);

/// Centralised typography tokens — use these everywhere instead of raw TextStyle.
/// Keeps font, weight, size, and letter-spacing consistent across the whole app.
class AppText {
  AppText._();

  // ── Display / Hero ────────────────────────────────────────────────────────
  static TextStyle display({Color? color}) => GoogleFonts.inter(
        fontSize: 30, fontWeight: FontWeight.w900,
        letterSpacing: -0.8, height: 1.08, color: color ?? AppTone.ink);

  static TextStyle headline({Color? color}) => GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w800,
        letterSpacing: -0.5, height: 1.15, color: color ?? AppTone.ink);

  // ── Titles ────────────────────────────────────────────────────────────────
  static TextStyle title({Color? color}) => GoogleFonts.inter(
        fontSize: 17, fontWeight: FontWeight.w800,
        letterSpacing: -0.2, height: 1.3, color: color ?? AppTone.ink);

  static TextStyle titleSm({Color? color}) => GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w700,
        letterSpacing: -0.1, height: 1.3, color: color ?? AppTone.ink);

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle body({Color? color}) => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w500,
        letterSpacing: 0.0, height: 1.5, color: color ?? AppTone.ink);

  static TextStyle bodyBold({Color? color}) => GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w700,
        letterSpacing: 0.0, height: 1.5, color: color ?? AppTone.ink);

  // ── Captions / Meta ───────────────────────────────────────────────────────
  static TextStyle caption({Color? color}) => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w500,
        letterSpacing: 0.1, height: 1.4, color: color ?? AppTone.muted);

  static TextStyle captionBold({Color? color}) => GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w700,
        letterSpacing: 0.1, height: 1.4, color: color ?? AppTone.muted);

  // ── Labels (ALL CAPS small chips) ─────────────────────────────────────────
  static TextStyle label({Color? color}) => GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w800,
        letterSpacing: 1.1, height: 1.2, color: color ?? AppTone.muted);

  // ── Monospace (codes, IMEI, tokens) ──────────────────────────────────────
  static TextStyle mono({double size = 13, Color? color, double spacing = 1.0}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size, fontWeight: FontWeight.w600,
        letterSpacing: spacing, height: 1.4, color: color ?? AppTone.ink);

  // ── Button ────────────────────────────────────────────────────────────────
  static TextStyle button({Color? color}) => GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w700,
        letterSpacing: 0.1, height: 1.0, color: color ?? Colors.white);

  static TextStyle buttonSm({Color? color}) => GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w700,
        letterSpacing: 0.1, height: 1.0, color: color ?? AppTone.ink);
}

Color roleAccent(AppUser user) =>
    user.isReseller ? AppTone.accent : AppTone.brand;
Color roleAccentDark(AppUser user) =>
    user.isReseller ? const Color(0xFF4F46E5) : AppTone.brandDark;
Color roleAccentLight(AppUser user) =>
    user.isReseller ? AppTone.accentLight : AppTone.brandLight;

Future<void> bootstrapEmiLockerApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  // Lock to portrait — the gyroscope should never rotate the dealer UI.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const EmiLockerApp());
}

class EmiLockerApp extends StatefulWidget {
  const EmiLockerApp({super.key});

  @override
  State<EmiLockerApp> createState() => _EmiLockerAppState();
}

class _EmiLockerAppState extends State<EmiLockerApp> {
  final api = ApiClient();
  Session? session;
  bool loading = true;
  bool _showOnboarding = false;
  late final SseService _sse = SseService(dio: api.dio, getToken: () => api.accessToken);

  @override
  void initState() {
    super.initState();
    api.onSessionExpired = _sessionExpired;
    _restore();
  }

  @override
  void dispose() {
    _sse.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final access = await storage.read(key: 'accessToken');
    final refresh = await storage.read(key: 'refreshToken');
    final rawUser = await storage.read(key: 'user');
    if (access != null && refresh != null && rawUser != null) {
      final user = AppUser.fromJson(asMap(jsonDecode(rawUser)));
      api.setTokens(accessToken: access, refreshToken: refresh);
      session = Session(user: user, accessToken: access, refreshToken: refresh);
      _sse.start();
    } else {
      final onboardingDone = await OnboardingScreen.isComplete();
      if (!onboardingDone) _showOnboarding = true;
      // Pre-populate local vault from Drive backup (survives reinstall)
      _tryRestoreVaultFromDrive();
    }
    setState(() => loading = false);
  }

  Future<void> _authenticated(Session next) async {
    api.setTokens(
      accessToken: next.accessToken,
      refreshToken: next.refreshToken,
    );
    await storage.write(key: 'accessToken', value: next.accessToken);
    await storage.write(key: 'refreshToken', value: next.refreshToken);
    await storage.write(key: 'user', value: jsonEncode(next.user.toJson()));
    setState(() => session = next);
    _sse.start();
    _maybeSyncVaultToDrive();
  }

  Future<void> _tryRestoreVaultFromDrive() async {
    try {
      if (!await GoogleVault.isBound()) return;
      final snapshot = await GoogleVault.restoreFromDrive();
      if (snapshot == null) return;
      final devices = List<Map<String, dynamic>>.from(snapshot['devices'] as List? ?? []);
      final keys    = List<Map<String, dynamic>>.from(snapshot['keys']    as List? ?? []);
      final dealerId = snapshot['dealer_id']?.toString() ?? '';
      if (dealerId.isNotEmpty && (devices.isNotEmpty || keys.isNotEmpty)) {
        if (devices.isNotEmpty) await LocalVault.syncDevices(dealerId, devices);
        if (keys.isNotEmpty)    await LocalVault.syncKeys(dealerId, keys);
      }
    } catch (_) {}
  }

  Future<void> _maybeSyncVaultToDrive() async {
    try {
      if (!await GoogleVault.isBound()) return;
      final snapshot = await LocalVault.read();
      if (snapshot == null || snapshot.isEmpty) return;
      await GoogleVault.syncVaultBackup(snapshot.toJson());
    } catch (_) {
      // Background operation — silent failure, never surfaces to user
    }
  }

  Future<void> _logout() async {
    _sse.stop();
    try {
      final refresh = await storage.read(key: 'refreshToken');
      await api.post('/api/v1/auth/logout',
          data: refresh != null ? {'refreshToken': refresh} : null);
    } catch (_) {}
    api.clearTokens();
    await storage.deleteAll();
    setState(() => session = null);
  }

  Future<void> _sessionExpired() async {
    _sse.stop();
    api.clearTokens();
    await storage.deleteAll();
    if (!mounted) return;
    setState(() {
      session = null;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseText = GoogleFonts.interTextTheme();
    return MaterialApp(
      title: 'EMI Locker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTone.brand,
          primary: AppTone.brand,
          secondary: AppTone.accent,
          error: AppTone.danger,
          surface: AppTone.surface,
        ),
        textTheme: baseText.apply(
          bodyColor: AppTone.ink,
          displayColor: AppTone.ink,
        ),
        scaffoldBackgroundColor: AppTone.page,
        cardTheme: const CardThemeData(
          elevation: 1,
          shadowColor: Color(0x10000000), // rgba(0,0,0,0.06)
          margin: EdgeInsets.zero,
          color: AppTone.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            // Removed border
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF3F4F6), // Soft gray background
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none, // No border by default
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTone.brand, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52), // Height 52px
            backgroundColor: AppTone.brand,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            side: const BorderSide(color: AppTone.subtle),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ), // Full pill
          side: BorderSide.none,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : session != null
          ? AppBiometricGate(
              onUsePassword: _logout,
              child: AppEventScope(
                events: _sse.events,
                child: Workspace(api: api, session: session!, onLogout: _logout),
              ),
            )
          : _showOnboarding
          ? OnboardingScreen(
              onComplete: () => setState(() => _showOnboarding = false),
            )
          : LoginScreen(api: api, onAuthenticated: _authenticated),
    );
  }
}

/// Provides the SSE event stream to any widget in the tree.
/// Access via: AppEventScope.of(context).listen(...)
class AppEventScope extends InheritedWidget {
  const AppEventScope({
    super.key,
    required this.events,
    required super.child,
  });

  final Stream<SseEvent> events;

  static Stream<SseEvent>? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppEventScope>()?.events;
  }

  @override
  bool updateShouldNotify(AppEventScope old) => events != old.events;
}

class ApiClient {
  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: configuredApiBaseUrl(),
        connectTimeout: _timeout('CONNECT_TIMEOUT'),
        receiveTimeout: _timeout('RECEIVE_TIMEOUT'),
        sendTimeout: _timeout('SEND_TIMEOUT'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_accessToken != null) {
            options.headers['Authorization'] = 'Bearer $_accessToken';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 &&
              !_refreshing &&
              _refreshToken != null) {
            _refreshing = true;
            try {
              if (await refresh()) {
                final options = error.requestOptions;
                options.headers['Authorization'] = 'Bearer $_accessToken';
                final response = await dio.fetch<dynamic>(options);
                _refreshing = false;
                return handler.resolve(response);
              }
            } catch (_) {
              // Fall through to session expiry handling below.
            } finally {
              _refreshing = false;
            }
          }
          if (error.response?.statusCode == 401 && _accessToken != null) {
            await expireSession();
          }
          handler.next(error);
        },
      ),
    );
  }

  late final Dio dio;
  String? _accessToken;
  String? _refreshToken;
  bool _refreshing = false;
  Future<void> Function()? onSessionExpired;

  static Duration _timeout(String key) =>
      Duration(milliseconds: int.tryParse(dotenv.env[key] ?? '') ?? 30000);

  String? get accessToken => _accessToken;

  void setTokens({required String accessToken, required String refreshToken}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  Future<void> expireSession() async {
    clearTokens();
    await storage.deleteAll();
    await onSessionExpired?.call();
  }

  String _path(String path) {
    if (path.startsWith('/api/v1/')) return path;
    if (path.startsWith('/api/')) return path.replaceFirst('/api/', '/api/v1/');
    if (path.startsWith('/')) return '/api/v1$path';
    return '/api/v1/$path';
  }

  Future<bool> refresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;
    final response = await dio.post<dynamic>(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = asMap(response.data);
    final access = data['accessToken']?.toString();
    final refresh = data['refreshToken']?.toString();
    if (access == null || refresh == null) return false;
    setTokens(accessToken: access, refreshToken: refresh);
    await storage.write(key: 'accessToken', value: access);
    await storage.write(key: 'refreshToken', value: refresh);
    return true;
  }

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      dio.get<dynamic>(_path(path), queryParameters: query);

  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
  }) => dio.post<dynamic>(_path(path), data: data, queryParameters: query);

  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
  }) => dio.put<dynamic>(_path(path), data: data, queryParameters: query);

  Future<Response<dynamic>> patch(String path, {dynamic data}) =>
      dio.patch<dynamic>(_path(path), data: data);

  Future<Response<dynamic>> delete(String path, {Map<String, dynamic>? query}) =>
      dio.delete<dynamic>(_path(path), queryParameters: query);
}

class Session {
  const Session({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });
  final AppUser user;
  final String accessToken;
  final String refreshToken;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.phone = '',
    this.shopName = '',
  });
  final String id;
  final String email;
  final String name;
  final String role;
  final String phone;
  final String shopName;

  bool get isReseller => role == 'reseller';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: text(json['id']),
    email: text(json['email']),
    name: text(json['name'], fallback: 'User'),
    role: text(json['role'], fallback: 'dealer').toLowerCase(),
    phone: text(json['phone']),
    shopName: text(json['shop_name'] ?? json['business_name']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'phone': phone,
    'shop_name': shopName,
  };
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });
  final ApiClient api;
  final ValueChanged<Session> onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final _otpController = TextEditingController();
  bool busy = false;
  String? error;
  bool _showOtp = false;
  String? _deviceFingerprint;
  int _errorShakeKey = 0;

  @override
  void initState() {
    super.initState();
    _loadOrGenFingerprint();
  }

  Future<void> _loadOrGenFingerprint() async {
    var fp = await storage.read(key: 'device_fingerprint');
    if (fp == null) {
      final rand = Random.secure();
      fp = List.generate(32, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await storage.write(key: 'device_fingerprint', value: fp);
    }
    if (mounted) setState(() => _deviceFingerprint = fp);
  }

  void _completeLogin(Map<String, dynamic> data) {
    final access = data['accessToken']?.toString();
    final refresh = data['refreshToken']?.toString();
    if (access == null || refresh == null) throw Exception('Tokens missing');
    widget.onAuthenticated(Session(
      user: AppUser.fromJson(asMap(data['user'])),
      accessToken: access,
      refreshToken: refresh,
    ));
  }

  String _deviceName() {
    try {
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      return Platform.localHostname;
    } catch (_) {
      return 'Mobile Device';
    }
  }

  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      final res = await widget.api.post('/api/v1/auth/login', data: {
        'email': email.text.trim(),
        'password': password.text,
        'device_fingerprint': _deviceFingerprint,
        'device_name': _deviceName(),
      });
      final data = asMap(res.data);
      if (data['requiresDeviceVerification'] == true) {
        setState(() { _showOtp = true; busy = false; });
        return;
      }
      _completeLogin(data);
    } catch (e) {
      setState(() { error = readableError(e); _errorShakeKey++; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() { busy = true; error = null; });
    try {
      final res = await widget.api.post('/api/v1/auth/verify-device-otp', data: {
        'email': email.text.trim(),
        'device_fingerprint': _deviceFingerprint,
        'otp': _otpController.text.trim(),
      });
      _completeLogin(asMap(res.data));
      // Offer biometric enrollment on first trust of this device
      _offerBiometricEnrollment();
    } catch (e) {
      setState(() { error = readableError(e); _errorShakeKey++; });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _offerBiometricEnrollment() async {
    final bio = BiometricService();
    final alreadyEnabled = await bio.isBiometricEnabled();
    if (alreadyEnabled) return;
    final available = await bio.isBiometricAvailable();
    if (!available || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enable fingerprint login?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        content: const Text(
          'Skip the email code on this device next time.\n'
          'Use your fingerprint or PIN instead.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () async {
              await bio.setBiometricEnabled(true);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Widget _buildApiChip() {
    final url = widget.api.dio.options.baseUrl;
    final host = Uri.tryParse(url)?.host ?? url;
    return Tooltip(
      message: url,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTone.page,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTone.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 13, color: AppTone.muted),
            const SizedBox(width: 5),
            Text(
              host.isEmpty ? url : host,
              style: const TextStyle(
                color: AppTone.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ThemeData _darkInputTheme() => ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(primary: Color(0xFF00A86B)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0A1220),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1C2D45), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1C2D45), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
      ),
      labelStyle: const TextStyle(color: Color(0xFF4B6080), fontSize: 14),
      prefixIconColor: const Color(0xFF4B6080),
    ),
  );

  Widget _buildLoginCard(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 450),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: AppTone.brand.withValues(alpha: 0.06),
              blurRadius: 40,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with breathing icon
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTone.brand,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTone.brand.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.security_rounded, size: 22, color: Colors.white),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.05, 1.05),
                      duration: 2800.ms,
                      curve: Curves.easeInOut,
                    ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMI Locker',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTone.ink,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Secure workspace access',
                      style: GoogleFonts.inter(
                        color: AppTone.muted,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            _LightLoginInput(
              controller: email,
              label: 'Email address',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _LightLoginInput(
              controller: password,
              label: 'Password',
              icon: Icons.lock_outline,
              obscure: true,
            ),
            if (_showOtp) ...[
              const SizedBox(height: 18),
              _InlineNotice(
                message: 'A verification code was sent to your email. Enter it below.',
                tone: AppTone.info,
                icon: Icons.mark_email_unread_outlined,
              ),
              const SizedBox(height: 12),
              _LightLoginInput(
                controller: _otpController,
                label: '6-digit verification code',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : () => setState(() => _showOtp = false),
                  style: TextButton.styleFrom(foregroundColor: AppTone.brand),
                  child: const Text('Use a different account'),
                ),
              ),
            ],
            AnimatedSize(
              duration: _medium,
              curve: Curves.easeOutCubic,
              child: error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _InlineNotice(
                        message: error!,
                        tone: AppTone.red,
                        icon: Icons.error_outline,
                      )
                          .animate(key: ValueKey(_errorShakeKey))
                          .shake(hz: 4, offset: const Offset(5, 0), duration: 400.ms),
                    ),
            ),
            const SizedBox(height: 24),
            _GradientLoginButton(
              busy: busy,
              showOtp: _showOtp,
              onPressed: busy ? null : (_showOtp ? _verifyOtp : login),
            ),
            const SizedBox(height: 24),
            // Demo section header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTone.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTone.accent.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_outline_rounded, size: 12, color: AppTone.accent),
                      const SizedBox(width: 5),
                      Text('TRY DEMO', style: AppText.label(color: AppTone.accent)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Divider(color: AppTone.line, height: 1)),
              ],
            ),
            const SizedBox(height: 10),
            _RoleDemoCard(
              role: 'Dealer',
              email: 'dealer@emi-locker.com',
              icon: Icons.storefront_rounded,
              accent: AppTone.brand,
              onPressed: () {
                email.text = 'dealer@emi-locker.com';
                password.text = 'Demo@123456';
              },
            ),
            const SizedBox(height: 8),
            _RoleDemoCard(
              role: 'Reseller',
              email: 'reseller@emi-locker.com',
              icon: Icons.group_rounded,
              accent: AppTone.accent,
              onPressed: () {
                email.text = 'reseller@emi-locker.com';
                password.text = 'Demo@123456';
              },
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms, delay: 100.ms)
          .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 820;
    const bg = Color(0xFFF8FFFE);

    if (compact) {
      return Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            // Aurora blobs — light pastel, slowly drifting
            Positioned(top: -80, left: -60,
              child: _DriftingBlob(color: AppTone.brand.withValues(alpha: 0.10), size: 340, delay: 0)),
            Positioned(bottom: -40, right: -40,
              child: _DriftingBlob(color: const Color(0xFF34D399).withValues(alpha: 0.08), size: 280, delay: 1200)),
            Positioned(top: 200, right: -80,
              child: _DriftingBlob(color: AppTone.accent.withValues(alpha: 0.05), size: 220, delay: 600)),
            // Shimmer top bar
            const Positioned(top: 0, left: 0, right: 0, child: _ShimmerTopBar()),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Breathing logo
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: AppTone.brand,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTone.brand.withValues(alpha: 0.30),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.security_rounded, size: 18, color: Colors.white),
                            )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scale(
                                  begin: const Offset(1, 1),
                                  end: const Offset(1.06, 1.06),
                                  duration: 2600.ms,
                                  curve: Curves.easeInOut,
                                ),
                            const SizedBox(width: 10),
                            Text(
                              'EMI Locker',
                              style: GoogleFonts.inter(
                                color: AppTone.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ],
                        )
                            .animate()
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: -0.03, end: 0),
                        const SizedBox(height: 20),
                        Text(
                          'Command centre\nfor device control',
                          style: GoogleFonts.inter(
                            color: AppTone.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                            height: 1.1,
                            letterSpacing: -0.7,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 380.ms, delay: 60.ms)
                            .slideY(begin: -0.02, end: 0),
                        const SizedBox(height: 6),
                        Text(
                          'Dealer & reseller workspace',
                          style: TextStyle(
                            color: AppTone.muted,
                            fontSize: 14,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 300.ms, delay: 100.ms),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
                          _buildLoginCard(context),
                          if (kDebugMode) ...[
                            const SizedBox(height: 16),
                            _buildApiChip(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Desktop layout
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Positioned(top: -120, left: -80,
            child: _DriftingBlob(color: AppTone.brand.withValues(alpha: 0.10), size: 480, delay: 0)),
          Positioned(bottom: -80, right: -60,
            child: _DriftingBlob(color: const Color(0xFF34D399).withValues(alpha: 0.08), size: 400, delay: 900)),
          Positioned(top: 120, right: 80,
            child: _DriftingBlob(color: AppTone.accent.withValues(alpha: 0.04), size: 260, delay: 1500)),
          const Positioned(top: 0, left: 0, right: 0, child: _ShimmerTopBar()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: const _LoginHeroPanel()
                            .animate()
                            .fadeIn(duration: 480.ms)
                            .slideX(begin: -0.03, end: 0),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLoginCard(context),
                            if (kDebugMode) ...[
                              const SizedBox(height: 14),
                              _buildApiChip(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Login hero panel (desktop left side)
class _LoginHeroPanel extends StatelessWidget {
  const _LoginHeroPanel();

  static const _features = [
    (Icons.key_rounded, 'Activation key management'),
    (Icons.phone_android_rounded, 'Remote device lock & unlock'),
    (Icons.route_rounded, 'Field agent location tracking'),
    (Icons.shield_rounded, 'Enterprise-grade security'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Top label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTone.brand.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'DEVICE FLEET MANAGEMENT',
              style: TextStyle(
                color: AppTone.brand,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 28),
          // Pulsing rings centered
          Center(child: _PulsingRingsWidget(size: 200)),
          const SizedBox(height: 32),
          // Headline
          Text(
            'Command centre\nfor financed\ndevice control',
            style: GoogleFonts.inter(
              color: AppTone.ink,
              fontWeight: FontWeight.w900,
              fontSize: 36,
              height: 1.07,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Dealer and reseller operations\nin one controlled workspace.',
            style: TextStyle(
              color: AppTone.muted,
              fontSize: 14,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 32),
          // Feature list — clean vertical lines
          ..._features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AppTone.brand.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(f.$1, size: 15, color: AppTone.brand.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text(
                  f.$2,
                  style: const TextStyle(
                    color: Color(0xFF6B8AAA),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _SixDigitCodeInput extends StatefulWidget {
  const _SixDigitCodeInput({required this.controller});
  final TextEditingController controller;

  @override
  State<_SixDigitCodeInput> createState() => _SixDigitCodeInputState();
}

class _SixDigitCodeInputState extends State<_SixDigitCodeInput> {
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    focus.dispose();
    super.dispose();
  }

  void _sync() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return GestureDetector(
      onTap: () => focus.requestFocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2FA code',
            style: TextStyle(
              color: AppTone.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Opacity(
                opacity: 0.01,
                child: TextField(
                  controller: widget.controller,
                  focusNode: focus,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
              Row(
                children: List.generate(6, (index) {
                  final filled = index < value.length;
                  final active =
                      focus.hasFocus && index == value.length.clamp(0, 5);
                  return Expanded(
                    child: AnimatedContainer(
                      duration: _fast,
                      margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTone.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active || filled
                              ? AppTone.brand
                              : AppTone.line,
                          width: active ? 1.8 : 1,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: AppTone.brand.withValues(alpha: 0.14),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        filled ? value[index] : '',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTone.ink,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Login-specific UI helpers ────────────────────────────────────────────

class _ShimmerTopBar extends StatelessWidget {
  const _ShimmerTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00A86B), Color(0xFF34D399), Color(0xFF059669)],
          ),
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .shimmer(duration: 2200.ms, color: Colors.white.withValues(alpha: 0.55)),
    );
  }
}

class _DriftingBlob extends StatelessWidget {
  const _DriftingBlob({required this.color, required this.size, this.delay = 0});
  final Color color;
  final double size;
  final int delay;

  @override
  Widget build(BuildContext context) {
    return _GlowBlob(color: color, size: size)
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(
          begin: 0,
          end: 22,
          duration: Duration(milliseconds: 4200 + delay),
          curve: Curves.easeInOut,
        )
        .moveX(
          begin: 0,
          end: 14,
          duration: Duration(milliseconds: 5500 + delay),
          curve: Curves.easeInOut,
        );
  }
}

class _LightLoginInput extends StatefulWidget {
  const _LightLoginInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  State<_LightLoginInput> createState() => _LightLoginInputState();
}

class _LightLoginInputState extends State<_LightLoginInput> {
  final focus = FocusNode();
  bool focused = false;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    focus.addListener(() => setState(() => focused = focus.hasFocus));
  }

  @override
  void dispose() { focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _fast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: focused
            ? [BoxShadow(
                color: AppTone.brand.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              )]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: focus,
        obscureText: widget.obscure && _obscured,
        keyboardType: widget.keyboardType,
        style: widget.obscure
            ? GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: AppTone.ink,
              )
            : GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppTone.ink,
              ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(
            color: focused ? AppTone.brand : AppTone.muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            widget.icon,
            color: focused ? AppTone.brand : AppTone.muted,
            size: 20,
          ),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppTone.muted,
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Premium role selector card used in the demo section of the login screen.
class _RoleDemoCard extends StatefulWidget {
  const _RoleDemoCard({
    required this.role,
    required this.email,
    required this.icon,
    required this.accent,
    required this.onPressed,
  });
  final String role;
  final String email;
  final IconData icon;
  final Color accent;
  final VoidCallback onPressed;

  @override
  State<_RoleDemoCard> createState() => _RoleDemoCardState();
}

class _RoleDemoCardState extends State<_RoleDemoCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: _fast,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
        decoration: BoxDecoration(
          color: _pressed ? widget.accent.withValues(alpha: 0.04) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _pressed ? widget.accent.withValues(alpha: 0.4) : const Color(0xFFE5E7EB),
            width: _pressed ? 1.5 : 1.0,
          ),
          boxShadow: _pressed
              ? [BoxShadow(color: widget.accent.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          children: [
            // Accent stripe
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: widget.accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Role icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(widget.icon, size: 16, color: widget.accent),
            ),
            const SizedBox(width: 10),
            // Role name + email
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.role, style: AppText.captionBold(color: AppTone.ink)),
                  const SizedBox(height: 1),
                  Text(
                    widget.email,
                    style: AppText.mono(size: 10, color: AppTone.muted, spacing: 0),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: widget.accent.withValues(alpha: 0.5)),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 260.ms, delay: 40.ms).slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _LoginInput extends StatefulWidget {
  const _LoginInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  State<_LoginInput> createState() => _LoginInputState();
}

class _LoginInputState extends State<_LoginInput> {
  final focus = FocusNode();
  bool focused = false;
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    focus.addListener(() => setState(() => focused = focus.hasFocus));
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _fast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: focused
            ? [BoxShadow(
                color: AppTone.brand.withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              )]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: focus,
        obscureText: widget.obscure && _obscured,
        keyboardType: widget.keyboardType,
        style: widget.obscure
            ? GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: Colors.white,
              )
            : GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(
            color: focused ? AppTone.brand : const Color(0xFF4B6080),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            widget.icon,
            color: focused ? AppTone.brand : const Color(0xFF4B6080),
            size: 20,
          ),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                    color: const Color(0xFF4B6080),
                  ),
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFF0A1220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1C2D45), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1C2D45), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _GradientLoginButton extends StatelessWidget {
  const _GradientLoginButton({
    required this.busy,
    required this.showOtp,
    required this.onPressed,
  });
  final bool busy;
  final bool showOtp;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: onPressed != null
              ? const LinearGradient(
                  colors: [Color(0xFF00A86B), Color(0xFF059669)],
                )
              : null,
          color: onPressed == null ? const Color(0xFFD1FAE5) : null,
          boxShadow: onPressed != null
              ? [BoxShadow(
                  color: const Color(0xFF00A86B).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                )]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          showOtp ? Icons.verified_rounded : Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          showOtp ? 'Verify device' : 'Sign in securely',
                          style: AppText.button(),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark-theme variant of the role demo card (used on the desktop/dark login panel).
class _DarkDemoButton extends StatefulWidget {
  const _DarkDemoButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  State<_DarkDemoButton> createState() => _DarkDemoButtonState();
}

class _DarkDemoButtonState extends State<_DarkDemoButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: _fast,
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_pressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFF0D1E30) : const Color(0xFF0A1220),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _pressed ? AppTone.brand.withValues(alpha: 0.4) : const Color(0xFF1C2D45),
          ),
          boxShadow: _pressed
              ? [BoxShadow(color: AppTone.brand.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: AppText.captionBold(color: const Color(0xFF4B6080)),
        ),
      ),
    );
  }
}

class _AppNotification {
  _AppNotification({
    required this.type,
    required this.title,
    required this.body,
    this.targetTab,
  }) : at = DateTime.now(), read = false;
  final String type;
  final String title;
  final String body;
  final int? targetTab; // tab index to navigate on tap
  final DateTime at;
  bool read;
}

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });
  final ApiClient api;
  final Session session;
  final VoidCallback onLogout;

  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int index = 0;
  bool _controlsVisible = true;
  StreamSubscription<SseEvent>? _sseSub;
  final List<_AppNotification> _notifications = [];

  int get _unreadCount => _notifications.where((n) => !n.read).length;

  void _pushNotification(_AppNotification n) {
    setState(() { _notifications.insert(0, n); });
  }

  void _markAllRead() {
    setState(() { for (final n in _notifications) n.read = true; });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream != null) {
      _sseSub = stream.listen((event) {
        if (!mounted) return;
        // Reseller tabs: 0=Dashboard 1=Dealers 2=Keys 3=Analytics
        // Dealer tabs:   0=Dashboard 1=Devices 2=Enroll 3=Keys 4=Tools
        final reseller = widget.session.user.isReseller;
        if (event.type == 'key_request_approved') {
          final qty  = event.data['quantity'];
          final tier = event.data['tier'] ?? 'standard';
          final tierLabel = tier == 'vip' ? 'VIP'
              : tier == 'premium' ? 'Premium' : 'Standard';
          _pushNotification(_AppNotification(
            type: 'key_request_approved',
            title: 'Keys Approved',
            body: 'Admin approved $qty $tierLabel key${qty == 1 ? '' : 's'}. Tap to view your stock.',
            targetTab: reseller ? 2 : 3, // Keys tab
          ));
        } else if (event.type == 'enrollment_complete') {
          _pushNotification(_AppNotification(
            type: 'enrollment_complete',
            title: 'Device Enrolled',
            body: '${event.data['deviceName'] ?? 'Device'} enrolled successfully. Tap to view.',
            targetTab: reseller ? null : 1, // Dealer → Devices tab
          ));
        } else if (event.type == 'device_locked') {
          _pushNotification(_AppNotification(
            type: 'device_locked',
            title: 'Device Locked',
            body: '${event.data['deviceName'] ?? 'A device'} was locked. Tap to view.',
            targetTab: reseller ? null : 1, // Dealer → Devices tab
          ));
        }
      });
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _setIndex(int i) => setState(() {
        index = i;
        _controlsVisible = true;
      });

  bool get isReseller => widget.session.user.isReseller;

  List<NavDestinationSpec> get pages => isReseller
      ? [
          NavDestinationSpec(
            'Dashboard',
            Icons.home_rounded,
            ResellerDashboard(api: widget.api),
          ),
          NavDestinationSpec(
            'Dealers',
            Icons.groups_rounded,
            ResellerDealers(api: widget.api),
          ),
          NavDestinationSpec(
            'Keys',
            Icons.key_rounded,
            ResellerKeys(api: widget.api),
          ),
          NavDestinationSpec(
            'Analytics',
            Icons.insights,
            ResellerAnalytics(api: widget.api),
          ),
        ]
      : [
          NavDestinationSpec(
            'Dashboard',
            Icons.home_rounded,
            DealerDashboard(
              api: widget.api,
              onNavigate: (page) => setState(() => index = page),
            ),
          ),
          NavDestinationSpec(
            'Devices',
            Icons.phone_android_rounded,
            DealerDevices(api: widget.api),
          ),
          NavDestinationSpec(
            'Enroll',
            Icons.qr_code_scanner,
            EnrollmentPage(
              api: widget.api,
              onNavigate: (page) => setState(() => index = page),
            ),
          ),
          NavDestinationSpec(
            'Keys',
            Icons.key_rounded,
            DealerKeys(api: widget.api),
          ),
          NavDestinationSpec(
            'Tools',
            Icons.build_circle,
            DealerTools(api: widget.api),
          ),
        ];

  void openSettings() {
    final settings = SettingsPage(
      api: widget.api,
      session: widget.session,
      onLogout: widget.onLogout,
    );
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.86,
          child: settings,
        ),
      );
      return;
    }
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Settings',
      transitionDuration: _medium,
      pageBuilder: (context, animation, secondaryAnimation) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: AppTone.surface,
          child: SizedBox(width: width > 900 ? 440 : 400, child: settings),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
    );
  }

  Widget _buildAnimatedSwitcher(
    List<NavDestinationSpec> destinations,
    int index,
  ) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          final delta = notification.scrollDelta ?? 0;
          final atTop = notification.metrics.pixels < 50;
          final shouldShow = atTop || delta < 0;
          if (shouldShow != _controlsVisible) {
            setState(() => _controlsVisible = shouldShow);
          }
        } else if (notification is ScrollEndNotification) {
          if (notification.metrics.pixels < 20 && !_controlsVisible) {
            setState(() => _controlsVisible = true);
          }
        }
        return false;
      },
      child: AnimatedSwitcher(
        duration: _medium,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return ScaleTransition(
            scale: Tween<double>(begin: 0.992, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(index),
          child: destinations[index].page,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = pages;
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 600;
    final tablet = width >= 600 && width <= 1100;
    final desktop = width > 1100;
    if (index >= destinations.length) index = 0;

    return Scaffold(
      backgroundColor: AppTone.page,
      body: Row(
        children: [
          if (desktop)
            Container(
              width: 272,
              decoration: BoxDecoration(
                color: AppTone.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 24,
                    offset: const Offset(8, 0),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      children: [
                        const _BrandMark(size: 36),
                        const SizedBox(width: 12),
                        Text(
                          'EMI Locker',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: _RoleBadge(
                      label: isReseller ? 'Reseller' : 'Dealer',
                      reseller: isReseller,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: destinations.length,
                      itemBuilder: (context, i) {
                        return _NavButton(
                              page: destinations[i],
                              selected: index == i,
                              accent: roleAccent(widget.session.user),
                              onTap: () => _setIndex(i),
                            )
                            .animate(delay: (35 * i).ms)
                            .fadeIn()
                            .slideX(begin: -0.05);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _UserPanel(
                      user: widget.session.user,
                      onSettings: openSettings,
                    ),
                  ),
                ],
              ),
            ),
          if (tablet)
            _WorkspaceRail(
              pages: destinations,
              index: index,
              user: widget.session.user,
              onSelected: _setIndex,
              onSettings: openSettings,
            ),
          Expanded(
            child: mobile
                ? SafeArea(
                    bottom: false,
                    child: Stack(
                      children: [
                        _buildAnimatedSwitcher(destinations, index),
                        Positioned(
                          top: 0,
                          right: 12,
                          child: IgnorePointer(
                            ignoring: !_controlsVisible,
                            child: _FloatingWorkspaceControls(
                              user: widget.session.user,
                              api: widget.api,
                              onSettings: openSettings,
                              notifications: _notifications,
                              unreadCount: _unreadCount,
                              onMarkAllRead: _markAllRead,
                              onNavigateTo: _setIndex,
                            )
                                .animate(target: _controlsVisible ? 1.0 : 0.0)
                                .fade(duration: _medium)
                                .slideY(
                                  begin: -0.8,
                                  end: 0,
                                  duration: _medium,
                                  curve: Curves.easeOutCubic,
                                ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      _buildAnimatedSwitcher(destinations, index),
                      Positioned(
                        top: 8,
                        right: 22,
                        child: _FloatingWorkspaceControls(
                          user: widget.session.user,
                          api: widget.api,
                          onSettings: openSettings,
                          notifications: _notifications,
                          unreadCount: _unreadCount,
                          onMarkAllRead: _markAllRead,
                          onNavigateTo: _setIndex,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: !mobile
          ? null
          : _MobileBottomNav(
              pages: destinations,
              index: index,
              accent: roleAccent(widget.session.user),
              onSelected: _setIndex,
            ),
    );
  }
}

class NavDestinationSpec {
  const NavDestinationSpec(this.title, this.icon, this.page);
  final String title;
  final IconData icon;
  final Widget page;
}

class _FloatingWorkspaceControls extends StatelessWidget {
  const _FloatingWorkspaceControls({
    required this.user,
    required this.api,
    required this.onSettings,
    required this.notifications,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onNavigateTo,
  });
  final AppUser user;
  final ApiClient api;
  final VoidCallback onSettings;
  final List<_AppNotification> notifications;
  final int unreadCount;
  final VoidCallback onMarkAllRead;
  final void Function(int tab) onNavigateTo;

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(user);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 2,
          height: 12,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTone.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AlertBell(
                  api: api,
                  accent: accent,
                  notifications: notifications,
                  unreadCount: unreadCount,
                  onMarkAllRead: onMarkAllRead,
                  onNavigateTo: onNavigateTo,
                ),
                const SizedBox(width: 2),
                _AvatarButton(user: user, onTap: onSettings),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertBell extends StatelessWidget {
  const _AlertBell({
    required this.api,
    required this.accent,
    required this.notifications,
    required this.unreadCount,
    required this.onMarkAllRead,
    required this.onNavigateTo,
  });
  final ApiClient api;
  final Color accent;
  final List<_AppNotification> notifications;
  final int unreadCount;
  final VoidCallback onMarkAllRead;
  final void Function(int tab) onNavigateTo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Alert Center',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton.filledTonal(
            onPressed: () {
              onMarkAllRead();
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _AlertCenterSheet(
                  api: api,
                  accent: accent,
                  notifications: notifications,
                  onNavigateTo: (tab) { Navigator.pop(context); onNavigateTo(tab); },
                ),
              );
            },
            icon: const Icon(Icons.notifications_active_outlined),
            style: IconButton.styleFrom(
              foregroundColor: accent,
              backgroundColor: accent.withValues(alpha: 0.1),
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: 2,
              right: 2,
              child: IgnorePointer(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _notifIcon(String type) {
  switch (type) {
    case 'key_request_approved': return Icons.key_rounded;
    case 'enrollment_complete':  return Icons.phone_android_rounded;
    case 'device_locked':        return Icons.lock_rounded;
    default:                     return Icons.notifications_rounded;
  }
}

Color _notifColor(String type) {
  switch (type) {
    case 'key_request_approved': return const Color(0xFF10B981);
    case 'enrollment_complete':  return const Color(0xFF3B82F6);
    case 'device_locked':        return const Color(0xFFF59E0B);
    default:                     return const Color(0xFF6B7280);
  }
}

String _timeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _AlertCenterSheet extends StatelessWidget {
  const _AlertCenterSheet({
    required this.api,
    required this.accent,
    required this.notifications,
    required this.onNavigateTo,
  });
  final ApiClient api;
  final Color accent;
  final List<_AppNotification> notifications;
  final void Function(int tab) onNavigateTo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.notifications_active_rounded, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alert Center',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: AppTone.ink,
                            ),
                          ),
                          Text(
                            notifications.isEmpty
                                ? 'All clear'
                                : '${notifications.length} notification${notifications.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12, color: AppTone.muted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Divider(color: AppTone.muted.withValues(alpha: 0.12), height: 1),
              const SizedBox(height: 12),

              // ── List ─────────────────────────────────────────────────────
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none_rounded,
                                size: 56, color: AppTone.muted.withValues(alpha: 0.25)),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications yet',
                              style: TextStyle(
                                color: AppTone.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Key approvals and device events\nwill appear here in real time.',
                              style: TextStyle(color: AppTone.muted, fontSize: 13, height: 1.5),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final n = notifications[i];
                          final color = _notifColor(n.type);
                          final tappable = n.targetTab != null;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: tappable ? () => onNavigateTo(n.targetTab!) : null,
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: AppTone.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.22),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Icon pill
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              color.withValues(alpha: 0.18),
                                              color.withValues(alpha: 0.08),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(_notifIcon(n.type), color: color, size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      // Text
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                                letterSpacing: -0.2,
                                                color: AppTone.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              n.body,
                                              style: TextStyle(
                                                color: AppTone.muted,
                                                fontSize: 13,
                                                height: 1.45,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Icon(Icons.schedule_rounded,
                                                    size: 11, color: AppTone.muted.withValues(alpha: 0.5)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _timeAgo(n.at),
                                                  style: TextStyle(
                                                    color: AppTone.muted.withValues(alpha: 0.6),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.1,
                                                  ),
                                                ),
                                                if (tappable) ...[
                                                  const Spacer(),
                                                  Text(
                                                    'View →',
                                                    style: TextStyle(
                                                      color: color,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 0.2,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    final status = text(alert['status'], fallback: 'active');
    final type = text(alert['alert_type'], fallback: 'alert');
    final color = status.toLowerCase() == 'resolved'
        ? AppTone.muted
        : type.contains('geo') || type.contains('lock')
        ? AppTone.warning
        : AppTone.info;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _InfoTile(
        icon: Icons.warning_amber_rounded,
        color: color,
        title: text(alert['title'], fallback: alertTypeTitle(type)),
        subtitle: [
          text(alert['message'], fallback: 'Review this alert.'),
          if (text(alert['created_at']).isNotEmpty)
            formatDateTime(alert['created_at']),
        ].join('\n'),
        trailing: StatusPill(label: alertStatusLabel(status), color: color),
      ),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({
    required this.pages,
    required this.index,
    required this.user,
    required this.onSelected,
    required this.onSettings,
  });
  final List<NavDestinationSpec> pages;
  final int index;
  final AppUser user;
  final ValueChanged<int> onSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTone.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const _BrandMark(size: 38),
          const SizedBox(height: 22),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: index,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.none,
              indicatorColor: roleAccentLight(user),
              destinations: pages
                  .map(
                    (page) => NavigationRailDestination(
                      icon: Tooltip(
                        message: page.title,
                        child: Icon(page.icon, color: AppTone.muted),
                      ),
                      selectedIcon: Icon(page.icon, color: roleAccent(user)),
                      label: Text(page.title),
                    ),
                  )
                  .toList(),
            ),
          ),
          _AvatarButton(user: user, onTap: onSettings),
        ],
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.pages,
    required this.index,
    required this.accent,
    required this.onSelected,
  });
  final List<NavDestinationSpec> pages;
  final int index;
  final Color accent;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: AppTone.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: pages.asMap().entries.map((entry) {
              final i = entry.key;
              final page = entry.value;
              final active = i == index;
              return Expanded(
                child: Tooltip(
                  message: page.title,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelected(i),
                    child: AnimatedScale(
                      scale: active ? 1.06 : 1,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: AnimatedContainer(
                        duration: _fast,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: active
                              ? accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              page.icon,
                              size: 21,
                              color: active ? accent : AppTone.muted,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              page.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: active ? accent : AppTone.muted,
                                fontWeight: active
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.user, required this.onTap});
  final AppUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Profile and settings',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: _ProfileAvatar(user: user, radius: 19),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user, required this.radius});
  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: roleAccentLight(user),
      radius: radius,
      child: Text(
        text(user.name, fallback: 'U').substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: roleAccentDark(user),
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, this.dark = false});
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? Colors.white : AppTone.ink,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.2) : AppTone.ink,
        ),
      ),
      child: Icon(
        Icons.security,
        size: size * 0.54,
        color: dark ? AppTone.emeraldDark : const Color(0xFF34D399),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, required this.reseller});
  final String label;
  final bool reseller;

  @override
  Widget build(BuildContext context) {
    final color = reseller ? AppTone.violet : AppTone.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.page,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final NavDestinationSpec page;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: _fast,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: active
                      ? widget.accent.withValues(alpha: 0.12)
                      : hovered
                      ? const Color(0xFFF3F4F6)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.page.icon,
                      size: 20,
                      color: active ? widget.accent : AppTone.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.page.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? widget.accent : AppTone.ink,
                          fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Left-edge active indicator bar
              Positioned(
                left: 0, top: 8, bottom: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: active ? 3 : 0,
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({required this.user, required this.onSettings});
  final AppUser user;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTone.page,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: roleAccentLight(user),
            radius: 18,
            child: Text(
              text(user.name, fallback: 'U').substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: roleAccentDark(user),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  user.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTone.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class DealerDashboard extends StatefulWidget {
  const DealerDashboard({
    super.key,
    required this.api,
    required this.onNavigate,
  });
  final ApiClient api;
  final ValueChanged<int> onNavigate;

  @override
  State<DealerDashboard> createState() => _DealerDashboardState();
}

class _DealerDashboardState extends State<DealerDashboard> {
  Future<void> Function()? _reload;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream != null) {
      _sseSub = stream.listen((event) {
        if (!mounted) return;
        const relevant = {
          'device_locked', 'device_unlocked', 'enrollment_complete',
          'grace_expired', 'payment_recorded',
        };
        if (relevant.contains(event.type)) {
          _reload?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Dealer dashboard',
      loader: () async {
        final stats = asMap((await widget.api.get('/api/v1/dealer/stats')).data);
        final keys = asMap((await widget.api.get('/api/v1/keys/my-keys')).data);
        final devices = asMap((await widget.api.get('/api/v1/dealer/devices')).data);
        return {
          'stats': stats,
          'keys': asList(keys, 'keys'),
          'devices': asList(devices, 'devices'),
        };
      },
      builder: (context, data, reload) {
        _reload = reload;
        final stats = asMap(data['stats']);
        final keys = (data['keys'] as List<Map<String, dynamic>>?) ?? [];
        final devices = (data['devices'] as List<Map<String, dynamic>>?) ?? [];
        final assignedKeys = countByStatus(keys, 'assigned');
        final activatedKeys = countByStatus(keys, 'activated');
        final lockedDevices = devices
            .where((device) => text(device['status']).toLowerCase() == 'locked')
            .length;
        final enrolledDevices = devices
            .where(
              (device) => text(device['status']).toLowerCase() == 'enrolled',
            )
            .length;
        return Page(
          title: 'Dealer dashboard',
          subtitle: 'Device and key overview',
          reload: reload,
          children: [
            StatGrid(
              cards: [
                StatCard(
                  'Total devices',
                  stats['total_devices'] ?? devices.length,
                  icon: Icons.devices,
                ),
                StatCard(
                  'Enrolled',
                  stats['enrolled_devices'] ?? enrolledDevices,
                  color: AppTone.blue,
                ),
                StatCard(
                  'Locked',
                  stats['locked_devices'] ?? lockedDevices,
                  color: AppTone.red,
                ),
                StatCard(
                  'Ready activation codes',
                  stats['assigned_keys'] ?? assignedKeys,
                  color: AppTone.brand,
                  icon: Icons.vpn_key_outlined,
                ),
                StatCard(
                  'Used by devices',
                  stats['activated_keys'] ?? activatedKeys,
                  color: AppTone.emerald,
                ),
                StatCard(
                  'Decoupled',
                  stats['decoupled_devices'],
                  color: AppTone.amber,
                ),
              ],
            ),
            Section(
              title: "Today's work",
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MiniFact(label: 'Ready codes', value: '$assignedKeys'),
                  _MiniFact(label: 'Enrolled', value: '$enrolledDevices'),
                  _MiniFact(label: 'Locked', value: '$lockedDevices'),
                  _MiniFact(
                    label: 'Attention',
                    value: '${lockedDevices + (assignedKeys == 0 ? 1 : 0)}',
                  ),
                ],
              ),
            ),
            Section(
              title: 'Quick actions',
              child: _DealerQuickActions(onNavigate: widget.onNavigate, api: widget.api),
            ),
            Section(
              title: 'Dashboard alerts',
              child: _DealerWarningStrip(
                assignedKeys: assignedKeys,
                lockedDevices: lockedDevices,
                deviceCount: devices.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DealerQuickActions extends StatelessWidget {
  const _DealerQuickActions({required this.onNavigate, required this.api});
  final ValueChanged<int> onNavigate;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        'Enroll device',
        Icons.qr_code_2_outlined,
        () => onNavigate(2),
      ),
      _QuickAction(
        'Search devices',
        Icons.search_rounded,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => DeviceSearchScreen(api: api))),
      ),
      _QuickAction(
        'Customer credit',
        Icons.credit_score_outlined,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => CustomerCreditScreen(api: api))),
      ),
      _QuickAction(
        'Fraud center',
        Icons.shield_outlined,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FraudCenterScreen(api: api))),
      ),
      _QuickAction(
        'Export NEIR',
        Icons.table_chart_outlined,
        () => onNavigate(4),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions
              .map(
                (action) => SizedBox(
                  width: compact
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 30) / 4,
                  child: OutlinedButton.icon(
                    onPressed: action.onTap,
                    icon: Icon(action.icon),
                    label: Text(action.label, overflow: TextOverflow.ellipsis),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _DealerWarningStrip extends StatelessWidget {
  const _DealerWarningStrip({
    required this.assignedKeys,
    required this.lockedDevices,
    required this.deviceCount,
  });
  final int assignedKeys;
  final int lockedDevices;
  final int deviceCount;

  @override
  Widget build(BuildContext context) {
    final warnings = <Widget>[
      if (assignedKeys == 0)
        const _InlineNotice(
          message:
              'No ready activation codes. Ask your reseller to send stock before enrolling another device.',
          tone: AppTone.amber,
          icon: Icons.key_off_outlined,
        ),
      if (lockedDevices > 0)
        _InlineNotice(
          message:
              '$lockedDevices locked devices need payment or support follow-up.',
          tone: AppTone.red,
          icon: Icons.lock_outline,
        ),
      if (deviceCount == 0)
        const _InlineNotice(
          message:
              'No enrolled devices yet. Start with enrollment after receiving ready activation codes.',
          tone: AppTone.blue,
          icon: Icons.info_outline,
        ),
    ];
    if (warnings.isEmpty) {
      return _WorkspaceClearPanel(
        deviceCount: deviceCount,
        assignedKeys: assignedKeys,
        lockedDevices: lockedDevices,
      );
    }
    return Column(
      children: warnings
          .map(
            (warning) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: warning,
            ),
          )
          .toList(),
    );
  }
}

class _WorkspaceClearPanel extends StatelessWidget {
  const _WorkspaceClearPanel({
    required this.deviceCount,
    required this.assignedKeys,
    required this.lockedDevices,
  });
  final int deviceCount;
  final int assignedKeys;
  final int lockedDevices;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTone.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTone.brand.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTone.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.check_circle_rounded, color: AppTone.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workspace is clear',
                      style: TextStyle(
                        color: AppTone.brand,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const Text(
                      'Keys and devices are in a healthy operating state.',
                      style: TextStyle(
                        color: AppTone.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ClearStat(
                icon: Icons.phone_android_rounded,
                label: 'Devices enrolled',
                value: '$deviceCount',
                color: AppTone.brand,
              ),
              const SizedBox(width: 10),
              _ClearStat(
                icon: Icons.vpn_key_rounded,
                label: 'Keys ready',
                value: '$assignedKeys',
                color: AppTone.info,
              ),
              const SizedBox(width: 10),
              _ClearStat(
                icon: Icons.lock_open_rounded,
                label: 'Locks active',
                value: '$lockedDevices',
                color: AppTone.amber,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClearStat extends StatelessWidget {
  const _ClearStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DealerDevices extends StatelessWidget {
  const DealerDevices({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Devices',
      loader: () async => asMap((await api.get('/api/v1/dealer/devices')).data),
      sseEvents: const ['device_locked', 'device_unlocked', 'enrollment_complete', 'grace_expired'],
      builder: (context, data, reload) {
        final devices = asList(data, 'devices');
        return Page(
          title: 'Devices',
          subtitle: '${devices.length} enrolled devices',
          reload: reload,
          children: [
            Section(
              title: 'Device list',
              child: DealerDeviceList(api: api, devices: devices),
            ),
          ],
        );
      },
    );
  }
}

class DealerDeviceList extends StatefulWidget {
  const DealerDeviceList({super.key, required this.api, required this.devices});
  final ApiClient api;
  final List<Map<String, dynamic>> devices;

  @override
  State<DealerDeviceList> createState() => _DealerDeviceListState();
}

class _DealerDeviceListState extends State<DealerDeviceList> {
  final search = TextEditingController();
  String statusFilter = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.devices.isEmpty) return const Empty('No devices found.');
    final filtered = widget.devices.where((device) {
      final status = text(device['status']).toLowerCase();
      final query = search.text.trim().toLowerCase();
      final haystack = [
        device['device_name'],
        device['imei'],
        device['brand'],
        device['model'],
        device['customer_name'],
      ].map(text).join(' ').toLowerCase();
      return (statusFilter == 'all' || status == statusFilter) &&
          (query.isEmpty || haystack.contains(query));
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search devices',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _StatusFilterChips(
              selected: statusFilter,
              options: const {
                'all': 'All',
                'enrolled': 'Enrolled',
                'locked': 'Locked',
                'unlocked': 'Unlocked',
                'decoupled': 'Decoupled',
                'disabled': 'Disabled',
              },
              onChanged: (value) => setState(() => statusFilter = value),
            ),
            if (search.text.isNotEmpty || statusFilter != 'all')
              TextButton.icon(
                onPressed: () {
                  search.clear();
                  setState(() => statusFilter = 'all');
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const Empty('No devices match this filter.')
        else
          Column(
            children: filtered
                .map((device) => DeviceTile(api: widget.api, device: device))
                .toList(),
          ),
      ],
    );
  }
}

class DeviceTile extends StatelessWidget {
  const DeviceTile({super.key, required this.api, required this.device});
  final ApiClient api;
  final Map<String, dynamic> device;

  @override
  Widget build(BuildContext context) {
    final status = text(device['status'], fallback: 'unknown');
    return _InfoTile(
      icon: Icons.phone_android,
      color: statusColor(status),
      title: text(device['device_name'], fallback: 'Device'),
      subtitle:
          '${text(device['brand'], fallback: 'Unknown brand')} ${text(device['model'])}\nIMEI: ${device['imei'] ?? 'unknown'}',
      trailing: StatusPill(label: status, color: statusColor(status)),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DeviceActions(api: api, device: device),
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({
    required this.selected,
    required this.options,
    required this.onChanged,
  });
  final String selected;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((entry) {
        final active = selected == entry.key;
        return ChoiceChip(
          selected: active,
          showCheckmark: false,
          label: Text(entry.value),
          avatar: active ? const Icon(Icons.check, size: 16) : null,
          onSelected: (_) => onChanged(entry.key),
        );
      }).toList(),
    );
  }
}

class DeviceActions extends StatelessWidget {
  const DeviceActions({super.key, required this.api, required this.device});
  final ApiClient api;
  final Map<String, dynamic> device;

  @override
  Widget build(BuildContext context) {
    final id = text(device['id']);
    final status = text(device['status'], fallback: 'unknown');
    final lock = text(device['lock_level'], fallback: 'NONE');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        text(device['device_name'], fallback: 'Device'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    StatusPill(label: status, color: statusColor(status)),
                  ],
                ),
                const SizedBox(height: 12),
                _SoftPanel(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _DetailFact(
                        'IMEI',
                        text(device['imei'], fallback: 'unknown'),
                      ),
                      _DetailFact('Lock level', lock),
                      _DetailFact(
                        'EMI status',
                        text(
                          device['emi_status'] ?? device['agreement_status'],
                          fallback: 'Not linked',
                        ),
                      ),
                      _DetailFact(
                        'Key ID',
                        text(
                          device['activation_key_id'],
                          fallback: 'Not available',
                        ),
                      ),
                      _DetailFact(
                        'Enrolled',
                        formatDateTime(
                          device['enrolled_at'] ?? device['created_at'],
                        ),
                      ),
                      _DetailFact(
                        'Customer',
                        text(device['customer_name'], fallback: 'Not captured'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SoftPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Sensitive actions',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => showDialog<void>(
                                    context: context,
                                    builder: (_) =>
                                        LockDialog(api: api, deviceId: id),
                                  ),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Submit lock request'),
                          ),
                          OutlinedButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    isDismissible: false,
                                    enableDrag: false,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                    ),
                                    builder: (_) =>
                                        LocationDialog(api: api, deviceId: id),
                                  ),
                            icon: const Icon(Icons.location_searching),
                            label: const Text('Pull location'),
                          ),
                          OutlinedButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => showDialog<void>(
                                    context: context,
                                    builder: (_) => CustomerMessageDialog(
                                      api: api,
                                      deviceId: id,
                                    ),
                                  ),
                            icon: const Icon(Icons.sms_outlined),
                            label: const Text('Send message'),
                          ),
                          OutlinedButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UnlockFlowScreen(
                                        api: api,
                                        deviceId: id,
                                        deviceName: text(device['device_name'],
                                            fallback: 'Device'),
                                      ),
                                    )),
                            icon: const Icon(Icons.lock_open_outlined),
                            label: const Text('Unlock device'),
                          ),
                          TextButton.icon(
                            onPressed: id.isEmpty
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LockDetailScreen(
                                        api: api,
                                        deviceId: id,
                                        deviceName: text(device['device_name'],
                                            fallback: 'Device'),
                                      ),
                                    )),
                            icon: const Icon(Icons.info_outline),
                            label: const Text('View lock detail'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (id.isNotEmpty)
                  _DeviceSettingsPanel(api: api, deviceId: id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceSettingsPanel extends StatefulWidget {
  const _DeviceSettingsPanel({required this.api, required this.deviceId});
  final ApiClient api;
  final String deviceId;

  @override
  State<_DeviceSettingsPanel> createState() => _DeviceSettingsPanelState();
}

class _DeviceSettingsPanelState extends State<_DeviceSettingsPanel> {
  bool _expanded = false;
  bool _busy = false;
  bool _loaded = false;

  int _graceHours = 72;
  String _lockLevel = 'FULL';

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final res = await widget.api.get(
        '/api/v1/dealer/devices/${widget.deviceId}/settings',
      );
      final data = asMap(res.data);
      if (mounted) {
        setState(() {
          _graceHours = int.tryParse('${data['offline_grace_hours'] ?? 72}') ?? 72;
          _lockLevel = text(data['default_lock_level'], fallback: 'FULL');
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.put(
        '/api/v1/dealer/devices/${widget.deviceId}/settings',
        data: {'offline_grace_hours': _graceHours, 'default_lock_level': _lockLevel},
      );
      if (mounted) snack(context, 'Device settings saved');
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _medium,
      curve: Curves.easeOutCubic,
      child: _SoftPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                setState(() => _expanded = !_expanded);
                if (!_loaded) _load();
              },
              child: Row(
                children: [
                  const Icon(Icons.tune_outlined, size: 18, color: AppTone.muted),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Device-specific settings',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTone.muted,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 14),
              _SettingsRow(
                label: 'Offline grace period',
                subtitle: 'Overrides dealer default for this device',
                child: DropdownButton<int>(
                  value: _graceHours,
                  underline: const SizedBox.shrink(),
                  items: [24, 48, 72, 96, 120, 168]
                      .map((h) => DropdownMenuItem(value: h, child: Text('${h}h')))
                      .toList(),
                  onChanged: (v) { if (v != null) setState(() => _graceHours = v); },
                ),
              ),
              _SettingsRow(
                label: 'Lock level',
                child: DropdownButton<String>(
                  value: _lockLevel,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'SOFT', child: Text('SOFT')),
                    DropdownMenuItem(value: 'FULL', child: Text('FULL')),
                  ],
                  onChanged: (v) { if (v != null) setState(() => _lockLevel = v); },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_busy ? 'Saving…' : 'Save'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTone.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? 'Not available' : value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class EnrollmentPage extends StatefulWidget {
  const EnrollmentPage({
    super.key,
    required this.api,
    required this.onNavigate,
  });
  final ApiClient api;
  final ValueChanged<int> onNavigate;

  @override
  State<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends State<EnrollmentPage> {
  late Future<int> _keyCountFuture = _loadKeyCount();
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream == null) return;
    _sseSub = stream.listen((event) {
      if (mounted && const {'enrollment_complete', 'key_request_approved'}.contains(event.type)) {
        setState(() => _keyCountFuture = _loadKeyCount());
      }
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<int> _loadKeyCount() async {
    final res = await widget.api.get('/api/v1/keys/my-keys', query: {'status': 'assigned'});
    final keys = asList(asMap(res.data), 'keys');
    return keys.where((k) => text(asMap(k)['status']).toLowerCase() == 'assigned').length;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _keyCountFuture,
      builder: (context, snapshot) {
        final keyCount = snapshot.data ?? 0;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        return Page(
          title: 'Enroll device',
          subtitle: 'Bind a new device to a customer',
          reload: () async => setState(() => _keyCountFuture = _loadKeyCount()),
          children: [
            StatGrid(cards: [
              StatCard(
                'Keys in stock',
                keyCount,
                color: keyCount == 0 ? AppTone.danger : AppTone.brand,
                icon: Icons.vpn_key_outlined,
              ),
            ]),
            if (keyCount == 0 && !loading)
              const _InlineNotice(
                message: 'No keys in stock. Ask your reseller to send stock before enrolling.',
                tone: AppTone.amber,
                icon: Icons.key_off_outlined,
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: keyCount == 0 || loading
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BindDeviceWizard(api: widget.api),
                        ),
                      ).then((_) => setState(() => _keyCountFuture = _loadKeyCount())),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Bind New Device'),
            ),
          ],
        );
      },
    );
  }
}

class DealerKeys extends StatefulWidget {
  const DealerKeys({super.key, required this.api});
  final ApiClient api;

  @override
  State<DealerKeys> createState() => _DealerKeysState();
}

class _DealerKeysState extends State<DealerKeys> {
  late Future<Map<String, dynamic>> _invFuture = _loadInventory();
  late Future<List<Map<String, dynamic>>> _keysFuture = _loadKeys();
  String _tierFilter = 'all';
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream == null) return;
    _sseSub = stream.listen((event) {
      if (mounted && const {'key_request_approved', 'grace_expired'}.contains(event.type)) {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadInventory() async {
    final res = await widget.api.get('/api/v1/dealer/keys/inventory');
    return asMap(res.data);
  }

  Future<List<Map<String, dynamic>>> _loadKeys() async {
    final res = await widget.api.get('/api/v1/keys/my-keys');
    return asList(asMap(res.data), 'keys');
  }

  Future<void> _reload() async {
    setState(() {
      _invFuture = _loadInventory();
      _keysFuture = _loadKeys();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_invFuture, _keysFuture]),
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final inv = snap.hasData ? asMap(snap.data![0]) : <String, dynamic>{};
        final keys = snap.hasData ? List<Map<String, dynamic>>.from(snap.data![1] as List) : <Map<String, dynamic>>[];

        final totalAssigned = _tierInt(inv, 'standard', 'assigned') +
            _tierInt(inv, 'premium', 'assigned') +
            _tierInt(inv, 'vip', 'assigned');
        final totalActivated = _tierInt(inv, 'standard', 'activated') +
            _tierInt(inv, 'premium', 'activated') +
            _tierInt(inv, 'vip', 'activated');

        return Page(
          title: 'Dealer keys',
          subtitle: loading
              ? 'Loading…'
              : '$totalAssigned ready for activation, $totalActivated used by devices',
          reload: _reload,
          children: [
            if (loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Tier cards row — NotificationListener prevents horizontal scroll
              // events from bubbling to the page-level pull-to-refresh handler
              NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    children: [
                      _KeyTierCard(
                        tier: 'standard',
                        assigned: _tierInt(inv, 'standard', 'assigned'),
                        quota: _tierInt(inv, 'standard', 'quota'),
                        selected: _tierFilter == 'standard',
                        onTap: () => setState(() => _tierFilter = _tierFilter == 'standard' ? 'all' : 'standard'),
                      ),
                      const SizedBox(width: 12),
                      _KeyTierCard(
                        tier: 'premium',
                        assigned: _tierInt(inv, 'premium', 'assigned'),
                        quota: _tierInt(inv, 'premium', 'quota'),
                        selected: _tierFilter == 'premium',
                        onTap: () => setState(() => _tierFilter = _tierFilter == 'premium' ? 'all' : 'premium'),
                      ),
                      const SizedBox(width: 12),
                      _KeyTierCard(
                        tier: 'vip',
                        assigned: _tierInt(inv, 'vip', 'assigned'),
                        quota: _tierInt(inv, 'vip', 'quota'),
                        selected: _tierFilter == 'vip',
                        onTap: () => setState(() => _tierFilter = _tierFilter == 'vip' ? 'all' : 'vip'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Section(
                title: 'Activation capacity',
                child: _KeyCapacitySummary(inv: inv, tierFilter: _tierFilter),
              ),
            ],
          ],
        );
      },
    );
  }

  int _tierInt(Map<String, dynamic> inv, String tier, String field) {
    final t = asMap(inv[tier]);
    return int.tryParse(t[field]?.toString() ?? '0') ?? 0;
  }
}

// ── Key Capacity Summary ──────────────────────────────────────────────────────

class _KeyCapacitySummary extends StatelessWidget {
  const _KeyCapacitySummary({required this.inv, required this.tierFilter});
  final Map<String, dynamic> inv;
  final String tierFilter;

  static const _tiers = ['standard', 'premium', 'vip'];
  static const _tierLabel = {'standard': 'Standard', 'premium': 'Premium', 'vip': 'VIP'};
  static const _tierIcon = {
    'standard': Icons.vpn_key_outlined,
    'premium': Icons.stars_outlined,
    'vip': Icons.workspace_premium_outlined,
  };
  static const _tierColor = {
    'standard': Color(0xFF8E8E93),
    'premium': Color(0xFF0A84FF),
    'vip': Color(0xFFBF5AF2),
  };

  int _val(String tier, String field) {
    final t = inv[tier];
    if (t == null) return 0;
    return int.tryParse((t as Map)[field]?.toString() ?? '0') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final tiers = tierFilter == 'all' ? _tiers : [tierFilter];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...tiers.map((tier) {
          final assigned = _val(tier, 'assigned');
          final quota = _val(tier, 'quota');
          final activated = _val(tier, 'activated');
          final progress = quota > 0 ? (assigned / quota).clamp(0.0, 1.0) : 0.0;
          final color = _tierColor[tier]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_tierIcon[tier], size: 16, color: color),
                      const SizedBox(width: 8),
                      Text(_tierLabel[tier]!, style: AppText.titleSm(color: color)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$assigned remaining',
                          style: AppText.captionBold(color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _CapFact(label: 'Quota', value: '$quota', color: AppTone.muted),
                      const SizedBox(width: 20),
                      _CapFact(label: 'Ready', value: '$assigned', color: color),
                      const SizedBox(width: 20),
                      _CapFact(label: 'Used', value: '$activated', color: AppTone.muted),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Keys are generated by your reseller. Contact them to increase quota.',
            style: AppText.caption(),
          ),
        ),
      ],
    );
  }
}

class _CapFact extends StatelessWidget {
  const _CapFact({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label(color: AppTone.muted)),
        const SizedBox(height: 2),
        Text(value, style: AppText.titleSm(color: color)),
      ],
    );
  }
}

// ── Key Tier Visual Card ──────────────────────────────────────────────────────

class _KeyTierCard extends StatelessWidget {
  const _KeyTierCard({
    required this.tier,
    required this.assigned,
    required this.quota,
    required this.selected,
    required this.onTap,
  });

  final String tier;
  final int assigned;
  final int quota;
  final bool selected;
  final VoidCallback onTap;

  static const _meta = {
    'standard': _TierMeta(
      label: 'Standard',
      colors: [Color(0xFF8E8E93), Color(0xFFAEAEB2)],
      icon: Icons.vpn_key_outlined,
      features: ['Device enrollment', 'EMI lock/unlock', 'Basic dashboard'],
    ),
    'premium': _TierMeta(
      label: 'Premium',
      colors: [Color(0xFF0A84FF), Color(0xFF30B0C7)],
      icon: Icons.stars_outlined,
      features: ['All Standard features', 'Fraud center', 'Credit score display'],
    ),
    'vip': _TierMeta(
      label: 'VIP',
      colors: [Color(0xFFBF5AF2), Color(0xFFFFD60A)],
      icon: Icons.workspace_premium_outlined,
      features: ['All Premium features', 'bKash payment link', 'Custom grace periods'],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final m = _meta[tier]!;
    final progress = quota > 0 ? (assigned / quota).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: m.colors,
          ),
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: Colors.white, width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: m.colors[0].withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(m.icon, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text(
                  m.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$assigned',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            const Text(
              'available',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'of $quota quota',
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
            const SizedBox(height: 10),
            ...m.features.map((f) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.white70, size: 11),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      f,
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}

class _TierMeta {
  const _TierMeta({
    required this.label,
    required this.colors,
    required this.icon,
    required this.features,
  });
  final String label;
  final List<Color> colors;
  final IconData icon;
  final List<String> features;
}

class DealerKeyInventory extends StatefulWidget {
  const DealerKeyInventory({super.key, required this.keys});
  final List<Map<String, dynamic>> keys;

  @override
  State<DealerKeyInventory> createState() => _DealerKeyInventoryState();
}

class _DealerKeyInventoryState extends State<DealerKeyInventory> {
  final search = TextEditingController();
  String statusFilter = 'all';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) {
      return const Empty('Waiting for reseller assignment.');
    }
    final readyCount = countByStatus(widget.keys, 'assigned');
    final filtered = widget.keys.where((key) {
      final status = text(key['status']).toLowerCase();
      final query = search.text.trim().toLowerCase();
      final keyString = text(key['key_string'] ?? key['key']).toLowerCase();
      return (statusFilter == 'all' || status == statusFilter) &&
          (query.isEmpty || keyString.contains(query));
    }).toList();
    final order = ['assigned', 'activated', 'revoked'];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final status in order) {
      grouped[status] = filtered
          .where((key) => text(key['status']).toLowerCase() == status)
          .toList();
    }
    final other = filtered
        .where((key) => !order.contains(text(key['status']).toLowerCase()))
        .toList();
    if (other.isNotEmpty) grouped['other'] = other;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readyCount == 0) ...[
          const _InlineNotice(
            message:
                'Waiting for reseller stock. Used codes below are history only.',
            tone: AppTone.amber,
            icon: Icons.schedule_outlined,
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search keys',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            _StatusFilterChips(
              selected: statusFilter,
              options: const {
                'all': 'All',
                'assigned': 'Ready',
                'activated': 'Used',
                'revoked': 'Cancelled',
              },
              onChanged: (value) => setState(() => statusFilter = value),
            ),
            if (search.text.isNotEmpty || statusFilter != 'all')
              TextButton.icon(
                onPressed: () {
                  search.clear();
                  setState(() => statusFilter = 'all');
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const Empty('No keys match this filter.')
        else
          ...grouped.entries
              .where((entry) => entry.value.isNotEmpty)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          StatusPill(
                            label: dealerKeyStatusLabel(entry.key),
                            color: statusColor(entry.key),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${entry.value.length} keys',
                            style: const TextStyle(
                              color: AppTone.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: entry.value
                            .map((key) => DealerKeyTile(keyRow: key))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

class DealerKeyTile extends StatelessWidget {
  const DealerKeyTile({super.key, required this.keyRow});
  final Map<String, dynamic> keyRow;

  @override
  Widget build(BuildContext context) {
    final status = text(keyRow['status'], fallback: 'assigned');
    final ready = status.toLowerCase() == 'assigned';
    final color = ready ? AppTone.brand : statusColor(status);
    return _InfoTile(
      icon: ready ? Icons.vpn_key_outlined : Icons.history,
      color: color,
      title: text(
        keyRow['key_string'] ?? keyRow['key'],
        fallback: 'Activation key',
      ),
      subtitle: [
        ready ? 'Ready for one device enrollment' : 'Read-only key history',
        if (text(keyRow['assigned_at']).isNotEmpty)
          'Received in stock: ${formatDateTime(keyRow['assigned_at'])}',
        if (text(keyRow['activated_at']).isNotEmpty)
          'Used by device: ${formatDateTime(keyRow['activated_at'])}',
        if (text(keyRow['created_at']).isNotEmpty)
          'Created: ${formatDateTime(keyRow['created_at'])}',
      ].join('\n'),
      trailing: StatusPill(label: dealerKeyStatusLabel(status), color: color),
    );
  }
}

class DealerTools extends StatelessWidget {
  const DealerTools({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Dealer tools',
      loader: () async => asMap((await api.get('/api/v1/dealer/devices')).data),
      builder: (context, data, reload) {
        final devices = asList(data, 'devices');
        return Page(
          title: 'Dealer tools',
          subtitle: 'Field operations and exports',
          reload: reload,
          children: [
            Section(
              title: 'NEIR export',
              child: ToolExportPanel(api: api, devices: devices),
            ),
            Section(
              title: 'Offline unlock — PADT support',
              child: _PadtSupportPanel(api: api, devices: devices),
            ),
            Section(
              title: 'Security & fraud center',
              child: _FraudCenterEntry(api: api),
            ),
          ],
        );
      },
    );
  }
}

class ToolExportPanel extends StatefulWidget {
  const ToolExportPanel({super.key, required this.api, required this.devices});
  final ApiClient api;
  final List<Map<String, dynamic>> devices;

  @override
  State<ToolExportPanel> createState() => _ToolExportPanelState();
}

class _ToolExportPanelState extends State<ToolExportPanel> {
  bool busy = false;
  String? lastExport;

  Future<void> exportNeir(BuildContext context) async {
    setState(() => busy = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['NEIR Export'];
      sheet.appendRow([
        TextCellValue('IMEI'),
        TextCellValue('Brand'),
        TextCellValue('Model'),
        TextCellValue('Status'),
      ]);
      for (final d in widget.devices) {
        sheet.appendRow([
          TextCellValue(text(d['imei'])),
          TextCellValue(text(d['brand'])),
          TextCellValue(text(d['model'])),
          TextCellValue(text(d['status'])),
        ]);
      }
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Excel export failed');
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/emi_locker_neir_export_$stamp.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'EMI Locker NEIR export');
      if (mounted && context.mounted) {
        setState(() => lastExport = file.path);
        snack(context, 'NEIR export ready: ${widget.devices.length} devices');
      }
    } catch (e) {
      if (context.mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.devices
        .where((device) => text(device['status']).toLowerCase() == 'locked')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoftPanel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailFact('Rows', '${widget.devices.length} devices'),
              _DetailFact('Locked included', '$locked devices'),
              _DetailFact('Filename', 'emi_locker_neir_export_[time].xlsx'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy || widget.devices.isEmpty
                ? null
                : () => exportNeir(context),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.table_chart),
            label: Text(busy ? 'Preparing export' : 'Export enrolled IMEIs'),
          ),
        ),
        if (lastExport != null) ...[
          const SizedBox(height: 12),
          _InlineNotice(
            message: 'Last export generated: $lastExport',
            tone: AppTone.emerald,
            icon: Icons.check_circle_outline,
          ),
        ],
      ],
    );
  }
}

// ─── PADT Support Panel ────────────────────────────────────────────────────

class _PadtSupportPanel extends StatefulWidget {
  const _PadtSupportPanel({required this.api, required this.devices});
  final ApiClient api;
  final List<Map<String, dynamic>> devices;

  @override
  State<_PadtSupportPanel> createState() => _PadtSupportPanelState();
}

class _PadtSupportPanelState extends State<_PadtSupportPanel> {
  String? _selectedDeviceId;
  int _graceHours = 4;          // default grace period
  bool _smsBusy = false;
  bool _revokeBusy = false;
  List<Map<String, dynamic>> _pendingPadt = [];
  Map<String, dynamic>? _activeGrace;   // active grace unlock for selected device

  static const _graceOptions = [
    (hours: 2,  label: '2 hours'),
    (hours: 4,  label: '4 hours'),
    (hours: 8,  label: '8 hours'),
    (hours: 24, label: '24 hours'),
  ];

  @override
  void initState() {
    super.initState();
    _loadPendingPadt();
  }

  Future<void> _loadPendingPadt() async {
    try {
      final res = await widget.api.get('/api/v1/dealer/padt/pending');
      if (mounted) {
        setState(() {
          _pendingPadt = List<Map<String, dynamic>>.from(
            asList(asMap(res.data), 'pending'),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _loadActiveGrace(String deviceId) async {
    try {
      final res = await widget.api.get('/api/v1/dealer/devices/$deviceId/grace-unlock');
      if (mounted) {
        setState(() {
          _activeGrace = asMap(res.data)['active'] as Map<String, dynamic>?;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _activeGrace = null);
    }
  }

  Future<void> _sendSmsOtp() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    setState(() => _smsBusy = true);
    try {
      final res = await widget.api.post(
        '/api/v1/dealer/devices/$id/paut/sms-otp',
        data: {'grace_hours': _graceHours},
      );
      final data = asMap(res.data);
      if (mounted) {
        snack(
          context,
          'Unlock code sent to ${text(data['masked_phone'], fallback: 'customer')}. '
          'Device unlocks for $_graceHours hours then re-locks automatically.',
        );
        // Refresh active grace display
        _loadActiveGrace(id);
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => _smsBusy = false);
    }
  }

  Future<void> _revokeGrace() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Re-lock device now?'),
        content: const Text(
          'This will mark the grace period as revoked. '
          'The device will lock at its next server check-in or when it loses connectivity.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTone.danger),
            child: const Text('Re-lock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _revokeBusy = true);
    try {
      await widget.api.delete('/api/v1/dealer/devices/$id/grace-unlock');
      if (mounted) {
        setState(() => _activeGrace = null);
        snack(context, 'Grace period revoked. Device will re-lock on next check-in.');
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => _revokeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.devices
        .where((d) => text(d['id']).isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Device selector ──────────────────────────────────────────────
        DropdownButtonFormField<String>(
          key: const ValueKey('padt_device_selector'),
          value: _selectedDeviceId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Select device',
            prefixIcon: Icon(Icons.phone_android_outlined),
          ),
          selectedItemBuilder: (context) => devices.map((d) {
            final label =
                '${text(d['device_name'] ?? d['model'], fallback: 'Device')} — ${text(d['imei'], fallback: '')}';
            return Text(label, overflow: TextOverflow.ellipsis, maxLines: 1);
          }).toList(),
          items: devices.map((d) {
            final name = text(d['device_name'] ?? d['model'], fallback: 'Device');
            final imei = text(d['imei'], fallback: '');
            return DropdownMenuItem(
              value: text(d['id']),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: AppText.bodyBold(), overflow: TextOverflow.ellipsis),
                  if (imei.isNotEmpty)
                    Text(imei, style: AppText.mono(size: 11, color: AppTone.muted), overflow: TextOverflow.ellipsis),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            setState(() {
              _selectedDeviceId = v;
              _activeGrace = null;
            });
            if (v != null) _loadActiveGrace(v);
          },
        ),
        const SizedBox(height: 16),

        // ── Active grace unlock banner ───────────────────────────────────
        if (_activeGrace != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTone.brand.withOpacity(0.08),
              border: Border.all(color: AppTone.brand.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_open_outlined, color: AppTone.brand, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Grace period active',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.brand),
                      ),
                      Text(
                        '${_activeGrace!['grace_hours']}h unlock · expires ${formatDateTime(_activeGrace!['expires_at'])}',
                        style: const TextStyle(fontSize: 12, color: AppTone.muted),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _revokeBusy ? null : _revokeGrace,
                  style: TextButton.styleFrom(foregroundColor: AppTone.danger),
                  child: _revokeBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Re-lock'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Grace period selector ────────────────────────────────────────
        const Text(
          'Grace period duration',
          style: TextStyle(fontSize: 12, color: AppTone.muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _graceOptions.map((opt) {
            final selected = _graceHours == opt.hours;
            return ChoiceChip(
              label: Text(opt.label),
              selected: selected,
              onSelected: (_) => setState(() => _graceHours = opt.hours),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'Device will unlock for $_graceHours hours, then auto-lock again.',
          style: const TextStyle(fontSize: 11, color: AppTone.muted),
        ),
        const SizedBox(height: 14),

        // ── Action buttons ───────────────────────────────────────────────
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _selectedDeviceId == null || _smsBusy ? null : _sendSmsOtp,
              icon: _smsBusy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sms_outlined),
              label: Text(_smsBusy ? 'Sending…' : 'Send SMS unlock code'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Customer calls you, you pick the grace time and send the code. '
          'No internet needed on their device — they enter the 6-digit code on the locked screen.',
          style: TextStyle(color: AppTone.muted, fontSize: 12),
        ),

        // ── Pending admin decoupling list ────────────────────────────────
        if (_pendingPadt.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Pending admin decoupling',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ..._pendingPadt.map((pt) {
            final expiry = pt['expires_at'] != null
                ? formatDateTime(pt['expires_at'])
                : 'Unknown';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InfoTile(
                icon: Icons.pending_outlined,
                color: AppTone.warning,
                title: '${text(pt['brand'])} ${text(pt['model'])}'.trim().isEmpty
                    ? 'Device'
                    : '${text(pt['brand'])} ${text(pt['model'])}'.trim(),
                subtitle: 'IMEI: ${text(pt['imei'])} · Expires: $expiry',
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _ResellerTierCard extends StatelessWidget {
  const _ResellerTierCard({
    required this.tier,
    required this.available,
    required this.assigned,
  });
  final String tier;
  final int available;
  final int assigned;

  static const _meta = _KeyTierCard._meta;

  @override
  Widget build(BuildContext context) {
    final m = _meta[tier]!;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: m.colors,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: m.colors[0].withOpacity(0.32),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(m.icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                m.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: available),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              '$v',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'in stock',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.25),
          ),
          const SizedBox(height: 8),
          Text(
            '$assigned sent to dealers',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ResellerDashboard extends StatelessWidget {
  const ResellerDashboard({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Reseller dashboard',
      loader: () async => asMap((await api.get('/api/v1/reseller/stats')).data),
      sseEvents: const ['key_request_approved'],
      builder: (context, stats, reload) => Page(
        title: 'Reseller dashboard',
        subtitle: 'Dealer network and key inventory',
        reload: reload,
        children: [
          Section(
            title: 'Key stock by tier',
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) => true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ResellerTierCard(
                      tier: 'standard',
                      available: stats['standard_available'] as int? ?? 0,
                      assigned: stats['standard_assigned'] as int? ?? 0,
                    ),
                    const SizedBox(width: 12),
                    _ResellerTierCard(
                      tier: 'premium',
                      available: stats['premium_available'] as int? ?? 0,
                      assigned: stats['premium_assigned'] as int? ?? 0,
                    ),
                    const SizedBox(width: 12),
                    _ResellerTierCard(
                      tier: 'vip',
                      available: stats['vip_available'] as int? ?? 0,
                      assigned: stats['vip_assigned'] as int? ?? 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
          StatGrid(
            cards: [
              StatCard('Dealers', stats['total_dealers'], icon: Icons.groups),
              StatCard(
                'Total in stock',
                stats['available_keys'],
                color: AppTone.violet,
              ),
              StatCard(
                'Sent to dealers',
                stats['assigned_keys'],
                color: AppTone.amber,
              ),
              StatCard(
                'Used by devices',
                stats['activated_keys'],
                color: AppTone.emerald,
              ),
              StatCard(
                'Pending requests',
                stats['pending_requests'],
                color: AppTone.red,
              ),
            ],
          ),
          Section(
            title: 'Credit intelligence',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.credit_score_outlined),
              label: const Text('View credit summary'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreditSummaryScreen(api: api),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Credit Summary Screen ────────────────────────────────────────────────────

class CreditSummaryScreen extends StatefulWidget {
  const CreditSummaryScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<CreditSummaryScreen> createState() => _CreditSummaryScreenState();
}

class _CreditSummaryScreenState extends State<CreditSummaryScreen> {
  bool _settling = false;

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await widget.api.get('/api/v1/reseller/credit');
    return List<Map<String, dynamic>>.from(
      (res.data['entries'] as List?) ?? [],
    );
  }

  Future<void> _settle(String entryId, Future<void> Function() reload) async {
    setState(() => _settling = true);
    try {
      await widget.api.patch('/api/v1/reseller/credit/$entryId/settle');
      await reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to settle — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _settling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DataPage<List<Map<String, dynamic>>>(
      title: 'Credit summary',
      loader: _load,
      builder: (context, entries, reload) {
        final pending = entries.where((e) => e['status'] == 'pending').toList();
        final settled = entries.where((e) => e['status'] == 'settled').toList();

        return Page(
          title: 'Credit summary',
          subtitle: '${pending.length} pending · ${settled.length} settled',
          reload: reload,
          children: [
            if (entries.isEmpty)
              const Empty('No credit entries yet. Entries appear when you send keys to dealers.')
            else ...[
              if (pending.isNotEmpty)
                Section(
                  title: 'Outstanding (${pending.length})',
                  child: Column(
                    children: pending.asMap().entries.map((e) {
                      return _CreditEntryCard(
                        entry: e.value,
                        onSettle: _settling
                            ? null
                            : () => _settle(e.value['id'] as String, reload),
                      ).animate(delay: (40 * e.key).ms).fadeIn(duration: 180.ms);
                    }).toList(),
                  ),
                ),
              if (settled.isNotEmpty)
                Section(
                  title: 'Settled (${settled.length})',
                  child: Column(
                    children: settled
                        .map((e) => _CreditEntryCard(entry: e, onSettle: null))
                        .toList(),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _CreditEntryCard extends StatelessWidget {
  const _CreditEntryCard({required this.entry, required this.onSettle});
  final Map<String, dynamic> entry;
  final VoidCallback? onSettle;

  @override
  Widget build(BuildContext context) {
    final dealerName = text(entry['dealer_name'], fallback: 'Dealer');
    final qty = entry['keys_quantity'] as int? ?? 0;
    final tier = text(entry['tier'], fallback: 'standard');
    final status = text(entry['status'], fallback: 'pending');
    final isPending = status == 'pending';
    final createdAt = entry['created_at'] != null
        ? formatDateTime(entry['created_at'])
        : '—';
    final dueDate = entry['due_date'] != null
        ? formatDateTime(entry['due_date'])
        : null;
    final settledAt = entry['settled_at'] != null
        ? formatDateTime(entry['settled_at'])
        : null;

    final tierColor = switch (tier) {
      'premium' => const Color(0xFF0A84FF),
      'vip' => const Color(0xFFBF5AF2),
      _ => AppTone.muted,
    };
    final tierLabel = switch (tier) {
      'premium' => 'Premium',
      'vip' => 'VIP',
      _ => 'Standard',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTone.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending ? AppTone.warning.withValues(alpha: 0.4) : AppTone.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dealerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPending ? AppTone.warning : AppTone.emerald)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPending ? 'Pending' : 'Settled',
                  style: TextStyle(
                    color: isPending ? AppTone.warning : AppTone.emerald,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$qty × $tierLabel',
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Sent $createdAt',
                style: const TextStyle(color: AppTone.muted, fontSize: 12),
              ),
            ],
          ),
          if (dueDate != null) ...[
            const SizedBox(height: 4),
            Text(
              'Due $dueDate',
              style: TextStyle(
                color: isPending ? AppTone.warning : AppTone.muted,
                fontSize: 12,
                fontWeight: isPending ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
          if (settledAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Settled $settledAt',
              style: const TextStyle(color: AppTone.emerald, fontSize: 12),
            ),
          ],
          if (onSettle != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSettle,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Mark as settled'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTone.emerald,
                  side: BorderSide(
                    color: AppTone.emerald.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ResellerDealers extends StatelessWidget {
  const ResellerDealers({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Dealers',
      loader: () async =>
          asMap((await api.get('/api/v1/reseller/dealers')).data),
      builder: (context, data, reload) {
        final dealers = asList(data, 'dealers');
        return Page(
          title: 'Dealers',
          subtitle: '${dealers.length} dealers',
          reload: reload,
          actions: [
            FilledButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                useSafeArea: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.90,
                  child: _CreateDealerWizard(api: api, onCreated: reload),
                ),
              ),
              icon: const Icon(Icons.person_add),
              label: const Text('Create dealer'),
            ),
          ],
          children: [
            Section(
              title: 'Dealer network',
              child: dealers.isEmpty
                  ? const Empty('No dealers found.')
                  : Column(
                      children: dealers
                          .map(
                            (d) =>
                                DealerTile(api: api, dealer: d, reload: reload),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class DealerTile extends StatelessWidget {
  const DealerTile({
    super.key,
    required this.api,
    required this.dealer,
    required this.reload,
  });
  final ApiClient api;
  final Map<String, dynamic> dealer;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final id = text(dealer['id']);
    return _InfoTile(
      icon: Icons.storefront,
      color: AppTone.blue,
      title: text(dealer['name'], fallback: 'Dealer'),
      subtitle:
          '${dealer['email'] ?? ''}\n${dealer['business_name'] ?? dealer['shop_name'] ?? ''}',
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'assign') {
            showDialog<void>(
              context: context,
              builder: (_) => AssignKeysDialog(
                api: api,
                dealerId: id,
                dealerName: text(dealer['name'], fallback: 'Dealer'),
                onAssigned: reload,
              ),
            );
            return;
          }
          try {
            await api.post('/api/v1/reseller/dealers/$id/$value');
            await reload();
          } catch (e) {
            if (context.mounted) snack(context, readableError(e));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'assign', child: Text('Assign keys')),
          PopupMenuItem(value: 'suspend', child: Text('Suspend')),
          PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        ],
      ),
    );
  }
}

class ResellerKeys extends StatelessWidget {
  const ResellerKeys({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Key quota',
      sseEvents: const ['key_request_approved'],
      loader: () async {
        final results = await Future.wait([
          api.get('/api/v1/reseller/quota'),
          api.get('/api/v1/reseller/keys/requests'),
          api.get('/api/v1/reseller/dealers'),
          api.get('/api/v1/reseller/credit'),
        ]);
        final quota    = asMap(results[0].data);
        final requests = asList(asMap(results[1].data), 'requests');
        final dealers  = asList(asMap(results[2].data), 'dealers');
        final movement = asList(asMap(results[3].data), 'entries');
        return {
          'quota':    quota,
          'requests': requests,
          'dealers':  dealers,
          'movement': movement,
        };
      },
      builder: (context, data, reload) {
        final quota    = asMap(data['quota']);
        final requests = (data['requests'] as List<Map<String, dynamic>>?) ?? [];
        final dealers  = (data['dealers']  as List<Map<String, dynamic>>?) ?? [];
        final movement = (data['movement'] as List<Map<String, dynamic>>?) ?? [];

        final qStandard = (quota['quota_standard'] as num?)?.toInt() ?? 0;
        final qPremium  = (quota['quota_premium']  as num?)?.toInt() ?? 0;
        final qVip      = (quota['quota_vip']      as num?)?.toInt() ?? 0;
        final totalQuota = qStandard + qPremium + qVip;

        final pendingRequests = requests
            .where((r) => text(r['status']).toLowerCase() == 'pending')
            .length;

        return Page(
          title: 'Key quota',
          subtitle: '$totalQuota activations available to send',
          reload: reload,
          actions: const [],
          children: [
            // ── Tier quota cards ────────────────────────────────────────
            Section(
              title: 'Available quota by tier',
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) => true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ResellerTierCard(tier: 'standard', available: qStandard, assigned: 0),
                      const SizedBox(width: 12),
                      _ResellerTierCard(tier: 'premium',  available: qPremium,  assigned: 0),
                      const SizedBox(width: 12),
                      _ResellerTierCard(tier: 'vip',      available: qVip,      assigned: 0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Actions ─────────────────────────────────────────────────
            Section(
              title: 'Actions',
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Request quota'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => RequestKeysDialog(
                          api: api,
                          quota: quota,
                          onSubmitted: reload,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Send to dealer'),
                      onPressed: dealers.isEmpty || totalQuota == 0
                          ? null
                          : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              useSafeArea: true,
                              builder: (_) => SizedBox(
                                height: MediaQuery.sizeOf(context).height * 0.86,
                                child: _SendKeysWizard(
                                  api: api,
                                  dealers: dealers,
                                  tierQuota: {
                                    'standard': qStandard,
                                    'premium':  qPremium,
                                    'vip':      qVip,
                                  },
                                  onAssigned: reload,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Stock movement ───────────────────────────────────────────
            Section(
              title: 'Stock movement',
              child: movement.isEmpty
                  ? const Empty('No transfers yet. Send quota to a dealer to see movement here.')
                  : Column(
                      children: movement.take(20).toList().asMap().entries.map((e) {
                        final entry = e.value;
                        final dealerName = text(entry['dealer_name'], fallback: 'Dealer');
                        final qty        = entry['keys_quantity'] as int? ?? 0;
                        final tier       = text(entry['tier'], fallback: 'standard');
                        final status     = text(entry['status'], fallback: 'pending');
                        final date       = formatDateTime(entry['created_at']);
                        final tierColor  = switch (tier) {
                          'premium' => const Color(0xFF0A84FF),
                          'vip'     => const Color(0xFFBF5AF2),
                          _         => AppTone.muted,
                        };
                        final tierLabel  = switch (tier) {
                          'premium' => 'Premium',
                          'vip'     => 'VIP',
                          _         => 'Standard',
                        };
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTone.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTone.line),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: tierColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    '$qty',
                                    style: TextStyle(
                                      color: tierColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$qty $tierLabel → $dealerName',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14),
                                    ),
                                    Text(date,
                                        style: const TextStyle(
                                            color: AppTone.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (status == 'settled'
                                          ? AppTone.emerald
                                          : AppTone.warning)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status == 'settled' ? 'Paid' : 'Pending',
                                  style: TextStyle(
                                    color: status == 'settled'
                                        ? AppTone.emerald
                                        : AppTone.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ).animate(delay: (30 * e.key).ms).fadeIn(duration: 180.ms);
                      }).toList(),
                    ),
            ),

            // ── Pending requests ─────────────────────────────────────────
            if (pendingRequests > 0)
              Section(
                title: 'Pending requests ($pendingRequests)',
                child: KeyRequestList(requests: requests),
              ),
          ],
        );
      },
    );
  }
}

class ResellerAnalytics extends StatelessWidget {
  const ResellerAnalytics({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Analytics',
      loader: () async => asMap((await api.get('/api/v1/reseller/stats')).data),
      builder: (context, stats, reload) => Page(
        title: 'Analytics',
        subtitle: 'Key movement summary',
        reload: reload,
        children: [
          Section(
            title: 'Key usage',
            child: Bars(
              values: {
                'In stock': stats['available_keys'],
                'Sent': stats['assigned_keys'],
                'Used': stats['activated_keys'],
                'Pending': stats['pending_requests'],
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResellerKeyHandoffPanel extends StatelessWidget {
  const _ResellerKeyHandoffPanel({
    required this.dealers,
    required this.availableCount,
    required this.assignedCount,
    required this.onRequestKeys,
    required this.onSendKeys,
  });
  final List<Map<String, dynamic>> dealers;
  final int availableCount;
  final int assignedCount;
  final VoidCallback onRequestKeys;
  final VoidCallback? onSendKeys;

  @override
  Widget build(BuildContext context) {
    final canSend = availableCount > 0 && onSendKeys != null;
    final stockAlreadySent = availableCount == 0 && assignedCount > 0;
    final title = canSend
        ? '$availableCount ready codes can be sent to dealers'
        : stockAlreadySent
        ? 'All approved stock has already been sent'
        : availableCount == 0
        ? 'No ready codes in reseller stock'
        : 'Create a dealer before sending keys';
    final subtitle = canSend
        ? 'Choose a dealer and quantity. The dealer will see them as ready activation codes.'
        : stockAlreadySent
        ? '$assignedCount codes are already with dealers. Request or approve more stock before sending again.'
        : availableCount == 0
        ? 'Request keys first. Once approved, use Send to dealer from here.'
        : 'Dealer accounts are required before stock can be assigned.';
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 54,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTone.violet.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.outgoing_mail, color: AppTone.violet),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTone.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onRequestKeys,
              icon: const Icon(Icons.add),
              label: const Text('Request keys'),
            ),
            OutlinedButton.icon(
              onPressed: onSendKeys,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send to dealer'),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.session,
    required this.onLogout,
  });
  final ApiClient api;
  final Session session;
  final VoidCallback onLogout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final current = TextEditingController();
  final next = TextEditingController();
  final biometric = BiometricService();
  bool biometricAvailable = false;
  bool biometricEnabled = false;

  // Dealer defaults state
  bool _defaultsBusy = false;
  int _graceHours = 72;
  int _warnHours = 12;
  int _checkinMinutes = 360;
  String _lockLevel = 'FULL';
  final _shopNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  // Vault state
  VaultSnapshot? _vaultSnapshot;

  @override
  void initState() {
    super.initState();
    loadBiometricState();
    if (!widget.session.user.isReseller) {
      _loadDealerDefaults();
      _loadVaultMeta();
    }
  }

  Future<void> _loadDealerDefaults() async {
    try {
      final res = await widget.api.get('/api/v1/dealer/settings');
      final data = asMap(res.data);
      if (!mounted) return;
      setState(() {
        _graceHours = int.tryParse('${data['offline_grace_hours'] ?? 72}') ?? 72;
        _warnHours = int.tryParse('${data['warning_threshold_hours'] ?? 12}') ?? 12;
        _checkinMinutes = int.tryParse('${data['checkin_interval_minutes'] ?? 360}') ?? 360;
        _lockLevel = text(data['default_lock_level'], fallback: 'FULL');
        _shopNameCtrl.text = text(data['lock_screen_dealer_name']);
        _phoneCtrl.text = text(data['lock_screen_dealer_phone']);
        _messageCtrl.text = text(data['lock_screen_message']);
      });
    } catch (_) {}
  }

  Future<void> _saveDealerDefaults() async {
    setState(() => _defaultsBusy = true);
    try {
      await widget.api.put(
        '/api/v1/dealer/settings',
        data: {
          'offline_grace_hours': _graceHours,
          'warning_threshold_hours': _warnHours,
          'checkin_interval_minutes': _checkinMinutes,
          'default_lock_level': _lockLevel,
          'lock_screen_dealer_name': _shopNameCtrl.text.trim().isEmpty
              ? null
              : _shopNameCtrl.text.trim(),
          'lock_screen_dealer_phone': _phoneCtrl.text.trim().isEmpty
              ? null
              : _phoneCtrl.text.trim(),
          'lock_screen_message': _messageCtrl.text.trim().isEmpty
              ? null
              : _messageCtrl.text.trim(),
        },
      );
      if (mounted) snack(context, 'Device defaults saved');
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => _defaultsBusy = false);
    }
  }

  Future<void> _loadVaultMeta() async {
    final snap = await LocalVault.read();
    if (mounted) setState(() => _vaultSnapshot = snap);
  }

  Future<void> _exportVault() async {
    final json = await LocalVault.exportJson();
    if (json == null) {
      if (mounted) snack(context, 'No cached data to export');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/emi_locker_vault_$stamp.json');
      await file.writeAsString(json);
      await Share.shareXFiles([XFile(file.path)], text: 'EMI Locker offline vault backup');
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    }
  }

  Future<void> _clearVault() async {
    await LocalVault.clear();
    if (mounted) {
      setState(() => _vaultSnapshot = null);
      snack(context, 'Cached data cleared');
    }
  }

  Future<void> loadBiometricState() async {
    final available = await biometric.isBiometricAvailable();
    final enabled = await biometric.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      biometricAvailable = available;
      biometricEnabled = enabled;
    });
  }

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    _shopNameCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> changePassword() async {
    try {
      await widget.api.post(
        '/api/v1/users/change-password',
        data: {'currentPassword': current.text, 'newPassword': next.text},
      );
      if (mounted) snack(context, 'Password changed');
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    }
  }

  Future<void> toggleBiometric(bool enabled) async {
    if (enabled) {
      final ok = await biometric.authenticate(
        reason: 'Enable biometric lock for EMI Locker',
      );
      if (!ok) return;
    }
    await biometric.setBiometricEnabled(enabled);
    if (mounted) setState(() => biometricEnabled = enabled);
  }

  Future<void> confirmAndLogout() async {
    final confirmed = await confirmLogout(context);
    if (!confirmed) return;
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              _ProfileAvatar(user: user, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      user.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTone.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Section(
            title: 'Profile',
            child: _SettingsProfileCard(user: user),
          ),
          const SizedBox(height: 14),
          Section(
            title: 'Security',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Biometric lock',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    biometricAvailable
                        ? 'Require device authentication when enabled.'
                        : 'No supported biometric or device credential found.',
                  ),
                  value: biometricEnabled && biometricAvailable,
                  onChanged: biometricAvailable ? toggleBiometric : null,
                ),
                const Divider(height: 22),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_outlined, color: AppTone.muted),
                  title: const Text('Trusted devices',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Devices that can log in without email verification.'),
                  trailing: const Icon(Icons.chevron_right, color: AppTone.muted),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: AppTone.surface,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => _TrustedDevicesSheet(api: widget.api),
                  ),
                ),
                const Divider(height: 22),
                Input(current, 'Current password', obscure: true),
                const SizedBox(height: 12),
                Input(next, 'New password', obscure: true),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: changePassword,
                    icon: const Icon(Icons.password),
                    label: const Text('Update password'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Section(title: 'Connection', child: const _ConnectionStatusCard()),
          if (!user.isReseller) ...[
            const SizedBox(height: 14),
            Section(
              title: 'Device defaults',
              child: _DealerDefaultsPanel(
                graceHours: _graceHours,
                warnHours: _warnHours,
                checkinMinutes: _checkinMinutes,
                lockLevel: _lockLevel,
                busy: _defaultsBusy,
                onGraceChanged: (v) => setState(() => _graceHours = v),
                onWarnChanged: (v) => setState(() => _warnHours = v),
                onCheckinChanged: (v) => setState(() => _checkinMinutes = v),
                onLockLevelChanged: (v) => setState(() => _lockLevel = v),
                onSave: _saveDealerDefaults,
              ),
            ),
            const SizedBox(height: 14),
            Section(
              title: 'Lock screen branding',
              child: _LockScreenBrandingPanel(
                shopName: _shopNameCtrl,
                phone: _phoneCtrl,
                message: _messageCtrl,
                busy: _defaultsBusy,
                onSave: _saveDealerDefaults,
              ),
            ),
            const SizedBox(height: 14),
            Section(
              title: 'Offline vault',
              child: _VaultStatusPanel(
                snapshot: _vaultSnapshot,
                onExport: _exportVault,
                onClear: _clearVault,
              ),
            ),
            const SizedBox(height: 14),
            Section(
              title: 'Google Drive backup',
              child: _GoogleDriveStatusTile(),
            ),
            const SizedBox(height: 14),
            Section(
              title: 'Evidence vault',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Manage NID evidence'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EvidenceVaultScreen(api: widget.api),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Section(
            title: 'Account',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: confirmAndLogout,
                style: FilledButton.styleFrom(backgroundColor: AppTone.danger),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsProfileCard extends StatelessWidget {
  const _SettingsProfileCard({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ProfileAvatar(user: user, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text(user.name, fallback: 'User'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTone.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ProfileDetailChip(
              icon: Icons.badge_outlined,
              label: 'Access',
              value: user.isReseller
                  ? 'Reseller workspace'
                  : 'Dealer workspace',
              color: accent,
            ),
            _ProfileDetailChip(
              icon: Icons.call_outlined,
              label: 'Phone',
              value: text(user.phone, fallback: 'Not added'),
              color: AppTone.info,
            ),
            _ProfileDetailChip(
              icon: Icons.storefront_outlined,
              label: user.isReseller ? 'Business' : 'Shop',
              value: text(user.shopName, fallback: 'Not added'),
              color: AppTone.warning,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileDetailChip extends StatelessWidget {
  const _ProfileDetailChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 250),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTone.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dealer settings panels ────────────────────────────────────────────────

class _DealerDefaultsPanel extends StatelessWidget {
  const _DealerDefaultsPanel({
    required this.graceHours,
    required this.warnHours,
    required this.checkinMinutes,
    required this.lockLevel,
    required this.busy,
    required this.onGraceChanged,
    required this.onWarnChanged,
    required this.onCheckinChanged,
    required this.onLockLevelChanged,
    required this.onSave,
  });
  final int graceHours;
  final int warnHours;
  final int checkinMinutes;
  final String lockLevel;
  final bool busy;
  final ValueChanged<int> onGraceChanged;
  final ValueChanged<int> onWarnChanged;
  final ValueChanged<int> onCheckinChanged;
  final ValueChanged<String> onLockLevelChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Applied to all new device enrollments. Override per device from the device detail screen.',
          style: TextStyle(color: AppTone.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _SettingsRow(
          label: 'Offline grace period',
          subtitle: 'Hours before lockout when no internet',
          child: DropdownButton<int>(
            value: graceHours,
            underline: const SizedBox.shrink(),
            items: [24, 48, 72, 96, 120, 168]
                .map((h) => DropdownMenuItem(value: h, child: Text('${h}h')))
                .toList(),
            onChanged: (v) { if (v != null) onGraceChanged(v); },
          ),
        ),
        _SettingsRow(
          label: 'Warning threshold',
          subtitle: 'Banner appears this many hours before lockout',
          child: DropdownButton<int>(
            value: warnHours,
            underline: const SizedBox.shrink(),
            items: [6, 12, 24, 48]
                .map((h) => DropdownMenuItem(value: h, child: Text('${h}h')))
                .toList(),
            onChanged: (v) { if (v != null) onWarnChanged(v); },
          ),
        ),
        _SettingsRow(
          label: 'Server check-in interval',
          subtitle: 'How often device phones home',
          child: DropdownButton<int>(
            value: checkinMinutes,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 60,   child: Text('1h')),
              DropdownMenuItem(value: 180,  child: Text('3h')),
              DropdownMenuItem(value: 360,  child: Text('6h')),
              DropdownMenuItem(value: 720,  child: Text('12h')),
              DropdownMenuItem(value: 1440, child: Text('24h')),
            ],
            onChanged: (v) { if (v != null) onCheckinChanged(v); },
          ),
        ),
        _SettingsRow(
          label: 'Default lock level',
          subtitle: 'SOFT = limited access / FULL = device locked',
          child: DropdownButton<String>(
            value: lockLevel,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'SOFT', child: Text('SOFT')),
              DropdownMenuItem(value: 'FULL', child: Text('FULL')),
            ],
            onChanged: (v) { if (v != null) onLockLevelChanged(v); },
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(busy ? 'Saving…' : 'Save defaults'),
          ),
        ),
      ],
    );
  }
}

class _LockScreenBrandingPanel extends StatelessWidget {
  const _LockScreenBrandingPanel({
    required this.shopName,
    required this.phone,
    required this.message,
    required this.busy,
    required this.onSave,
  });
  final TextEditingController shopName;
  final TextEditingController phone;
  final TextEditingController message;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This text is shown on the customer\'s locked device screen.',
          style: TextStyle(color: AppTone.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Input(shopName, 'Shop name on lock screen'),
        const SizedBox(height: 10),
        Input(phone, 'Contact number on lock screen'),
        const SizedBox(height: 10),
        Input(message, 'Custom message (optional)'),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(busy ? 'Saving…' : 'Save branding'),
          ),
        ),
      ],
    );
  }
}

class _VaultStatusPanel extends StatelessWidget {
  const _VaultStatusPanel({
    required this.snapshot,
    required this.onExport,
    required this.onClear,
  });
  final VaultSnapshot? snapshot;
  final VoidCallback onExport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoftPanel(
          child: Row(
            children: [
              Icon(
                snap != null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: snap != null ? AppTone.brand : AppTone.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: snap != null
                    ? Text(
                        'Last synced ${_ago(snap.syncedAt)} · '
                        '${snap.devices.length} devices · '
                        '${snap.keys.length} keys',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      )
                    : const Text(
                        'No cached data yet. Browse your devices or keys to populate the vault.',
                        style: TextStyle(color: AppTone.muted, fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: snap != null ? onExport : null,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export backup'),
            ),
            OutlinedButton.icon(
              onPressed: snap != null ? onClear : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear cache'),
            ),
          ],
        ),
      ],
    );
  }

  static String _ago(DateTime? dt) {
    if (dt == null) return 'unknown';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.child,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(color: AppTone.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

// ── Trusted Devices Sheet ─────────────────────────────────────────────────────

class _TrustedDevicesSheet extends StatefulWidget {
  const _TrustedDevicesSheet({required this.api});
  final ApiClient api;

  @override
  State<_TrustedDevicesSheet> createState() => _TrustedDevicesSheetState();
}

class _TrustedDevicesSheetState extends State<_TrustedDevicesSheet> {
  late Future<List<Map<String, dynamic>>> _devicesFuture = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await widget.api.get('/api/v1/auth/trusted-devices');
    return List<Map<String, dynamic>>.from(asList(asMap(res.data), 'devices'));
  }

  Future<void> _remove(String id) async {
    await widget.api.delete('/api/v1/auth/trusted-devices/$id');
    setState(() => _devicesFuture = _load());
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scroll) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTone.subtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Trusted Devices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTone.ink)),
              const SizedBox(height: 4),
              const Text('Devices below can log in with only your password.',
                  style: TextStyle(fontSize: 13, color: AppTone.muted)),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _devicesFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final devices = snap.data ?? [];
                    if (devices.isEmpty) {
                      return const Center(
                        child: Text('No trusted devices yet.',
                            style: TextStyle(color: AppTone.muted)),
                      );
                    }
                    return ListView.separated(
                      controller: scroll,
                      itemCount: devices.length,
                      separatorBuilder: (_, _i) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = devices[i];
                        final name = text(d['device_name']).isEmpty ? 'Unknown device' : text(d['device_name']);
                        final lastUsed = text(d['last_used_at']);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_android_outlined, color: AppTone.muted),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: lastUsed.isNotEmpty
                              ? Text('Last used: ${lastUsed.substring(0, 10)}',
                                  style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTone.danger),
                            tooltip: 'Remove device',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Remove device?'),
                                  content: Text('$name will need email verification on next login.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                                  ],
                                ),
                              );
                              if (confirm == true) _remove(text(d['id']));
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppTone.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.cloud_done_outlined,
            color: AppTone.brand,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection OK',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 2),
              Text(
                'Secure dealer services are reachable.',
                style: TextStyle(
                  color: AppTone.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LockDialog extends StatefulWidget {
  const LockDialog({super.key, required this.api, required this.deviceId});
  final ApiClient api;
  final String deviceId;

  @override
  State<LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends State<LockDialog> {
  String reason = 'EMI_OVERDUE';
  final note = TextEditingController();

  Future<void> submit() async {
    try {
      final response = await widget.api.post(
        '/api/v1/lock/request',
        data: {
          'deviceId': widget.deviceId,
          'reason': reason,
          'note': note.text,
        },
      );
      if (mounted) {
        Navigator.pop(context);
        snack(
          context,
          'Decision: ${asMap(response.data)['decision'] ?? 'submitted'}',
        );
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lock request'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: const [
                DropdownMenuItem(
                  value: 'EMI_OVERDUE',
                  child: Text('EMI overdue'),
                ),
                DropdownMenuItem(
                  value: 'SUSPECTED_FRAUD',
                  child: Text('Suspected fraud'),
                ),
                DropdownMenuItem(
                  value: 'SUSPECTED_SALE',
                  child: Text('Suspected sale'),
                ),
                DropdownMenuItem(
                  value: 'DEVICE_STOLEN',
                  child: Text('Device stolen'),
                ),
              ],
              onChanged: (value) => setState(() => reason = value ?? reason),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: submit, child: const Text('Submit')),
      ],
    );
  }
}

class LocationDialog extends StatefulWidget {
  const LocationDialog({super.key, required this.api, required this.deviceId});
  final ApiClient api;
  final String deviceId;

  @override
  State<LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<LocationDialog> {
  String message = 'Ready.';
  bool _busy = false;
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  DateTime? _cooldownUntil;
  String? _pullId;
  Map<String, dynamic>? _location;
  int _pollAttempts = 0;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> pull() async {
    if (_busy || _cooldownActive) return;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {
      _location = null;
      _pullId = null;
      _pollAttempts = 0;
    });
    setState(() { _busy = true; message = 'Sending pull request…'; });
    try {
      final response = await widget.api.post(
        '/api/v1/location/${widget.deviceId}/pull',
        data: <String, dynamic>{},
      );
      final data = asMap(response.data);
      final payload = asMap(data['data']);
      final pullId = text(payload['pullId']);
      setState(() => message = data['message']?.toString() ?? 'Pull sent.');
      if (!mounted) return;
      setState(() {
        _pullId = pullId.isEmpty ? null : pullId;
        message = 'Pull request accepted. Waiting for device location...';
      });
      _startPolling();
    } catch (e) {
      setState(() => message = readableError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    unawaited(_pollOnce());
  }

  Future<void> _pollOnce() async {
    if (!mounted) return;
    _pollAttempts += 1;
    try {
      final response = await widget.api.get(
        '/api/v1/location/${widget.deviceId}/history?limit=10',
      );
      final rows = asList(response.data, 'data');
      Map<String, dynamic>? match;

      if (_pullId != null) {
        for (final row in rows) {
          if (text(row['pullId']) == _pullId) {
            match = row;
            break;
          }
        }
      }

      if (match == null) {
        for (final row in rows) {
          if (text(row['latitude']).isNotEmpty &&
              text(row['longitude']).isNotEmpty) {
            match = row;
            break;
          }
        }
      }

      if (!mounted) return;
      if (match != null) {
        _pollTimer?.cancel();
        _pollTimer = null;
        setState(() {
          _location = match;
          message = 'Location received.';
        });
        _startCooldown();
        return;
      }

      if (_pollAttempts >= 30) {
        _pollTimer?.cancel();
        _pollTimer = null;
        setState(() {
          message = 'No location response within 60 seconds.';
        });
      } else {
        setState(() {
          message = 'Waiting for device location... ${_pollAttempts * 2}s';
        });
      }
    } catch (e) {
      if (!mounted) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() => message = readableError(e));
    }
  }

  bool get _cooldownActive {
    final until = _cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownUntil = DateTime.now().add(const Duration(seconds: 10)));
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_cooldownActive) {
        timer.cancel();
        setState(() => _cooldownUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final lat = text(location?['latitude']);
    final lng = text(location?['longitude']);
    final latValue = double.tryParse(lat);
    final lngValue = double.tryParse(lng);
    final accuracy = double.tryParse(text(location?['accuracy'])) ?? 0;
    final cooldownSeconds = _cooldownUntil == null
        ? 0
        : _cooldownUntil!.difference(DateTime.now()).inSeconds.clamp(0, 10);
    final mapsUrl = lat.isNotEmpty && lng.isNotEmpty
        ? 'https://maps.google.com/?q=$lat,$lng'
        : '';

    // Bottom sheet layout — respects Samsung/OEM nav bar insets automatically
    // via useSafeArea: true on the showModalBottomSheet call site.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle zone — only this area can drag-dismiss the sheet
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                Navigator.pop(context);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 20, color: AppTone.brand),
                  const SizedBox(width: 8),
                  Text('Pull location', style: AppText.title()),
                  const Spacer(),
                  // Visual handle pill
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: AppTone.subtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          // Status / progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(message, style: AppText.body(color: AppTone.muted)),
          ),
          if (_pollTimer != null && location == null) ...[
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(),
            ),
          ],
          // Map — full width, only shown when location arrives
          if (location != null && latValue != null && lngValue != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(latValue, lngValue),
                  zoom: accuracy > 200 ? 15 : 17,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('device-location'),
                    position: LatLng(latValue, lngValue),
                    infoWindow: const InfoWindow(title: 'Device location'),
                  ),
                },
                circles: {
                  if (accuracy > 0)
                    Circle(
                      circleId: const CircleId('accuracy'),
                      center: LatLng(latValue, lngValue),
                      radius: accuracy,
                      strokeColor: AppTone.brand,
                      strokeWidth: 2,
                      fillColor: AppTone.brand.withValues(alpha: 0.14),
                    ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ],
          // Coordinate facts
          if (location != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _LocationValue(label: 'Latitude', value: lat),
                  _LocationValue(label: 'Longitude', value: lng),
                  _LocationValue(
                    label: 'Accuracy',
                    value: '${text(location['accuracy'], fallback: '?')} m',
                  ),
                  _LocationValue(
                    label: 'Time',
                    value: formatDateTime(location['timestamp']),
                  ),
                ],
              ),
            ),
          ],
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: (_busy || _cooldownActive) ? null : pull,
                    child: _busy
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _cooldownActive
                                ? 'Ready in ${cooldownSeconds}s'
                                : location == null ? 'Pull now' : 'Pull again',
                            style: AppText.button(),
                          ),
                  ),
                ),
                if (mapsUrl.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(mapsUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Maps'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationValue extends StatelessWidget {
  const _LocationValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTone.muted,
                ),
          ),
          SelectableText(
            text(value, fallback: 'Unknown'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class CustomerMessageDialog extends StatefulWidget {
  const CustomerMessageDialog({
    super.key,
    required this.api,
    required this.deviceId,
  });
  final ApiClient api;
  final String deviceId;

  @override
  State<CustomerMessageDialog> createState() => _CustomerMessageDialogState();
}

class _CustomerMessageDialogState extends State<CustomerMessageDialog> {
  final message = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final body = message.text.trim();
    if (body.isEmpty) {
      snack(context, 'Write a customer message first.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.post(
        '/api/v1/notifications/message',
        data: {'deviceId': widget.deviceId, 'message': body},
      );
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Message queued for the customer device.');
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send message to customer device'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: message,
          maxLength: 160,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Message',
            hintText: 'Example: Please visit the store about your EMI payment.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : send,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Send message'),
        ),
      ],
    );
  }
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.actions,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
          insetPadding: const EdgeInsets.all(18),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTone.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTone.emerald),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTone.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(child: child),
          ),
          actions: actions,
        )
        .animate()
        .fadeIn(duration: 180.ms)
        .scale(
          begin: const Offset(0.985, 0.985),
          end: const Offset(1, 1),
          curve: Curves.easeOutCubic,
        );
  }
}

class RequestKeysDialog extends StatefulWidget {
  const RequestKeysDialog({
    super.key,
    required this.api,
    required this.quota,
    required this.onSubmitted,
  });
  final ApiClient api;
  final Map<String, dynamic> quota;
  final Future<void> Function() onSubmitted;

  @override
  State<RequestKeysDialog> createState() => _RequestKeysDialogState();
}

class _RequestKeysDialogState extends State<RequestKeysDialog> {
  final quantity = TextEditingController(text: '5');
  final justification = TextEditingController(
    text: 'Dealer inventory replenishment',
  );
  String _tier = 'standard';
  String? error;
  bool busy = false;

  int get monthlyQuota =>
      int.tryParse('${widget.quota['monthly_quota'] ?? 100}') ?? 100;
  int get usedKeys => int.tryParse('${widget.quota['used_keys'] ?? 0}') ?? 0;
  int get remainingQuota =>
      (monthlyQuota - usedKeys).clamp(0, monthlyQuota).toInt();
  int get maxPerRequest =>
      (monthlyQuota * 0.2).floor().clamp(1, monthlyQuota).toInt();
  int get requestedQuantity => int.tryParse(quantity.text.trim()) ?? 0;

  @override
  void dispose() {
    quantity.dispose();
    justification.dispose();
    super.dispose();
  }

  void adjustQuantity(int delta) {
    final next = (requestedQuantity + delta).clamp(1, maxPerRequest);
    setState(() {
      quantity.text = '$next';
      error = null;
    });
  }

  String? validate() {
    if (requestedQuantity <= 0) return 'Enter a valid quantity.';
    if (requestedQuantity > maxPerRequest) {
      return 'Maximum request size is $maxPerRequest keys.';
    }
    if (requestedQuantity > remainingQuota) {
      return 'Only $remainingQuota keys remain in this monthly quota.';
    }
    if (justification.text.trim().length < 10) {
      return 'Add a short justification for admin review.';
    }
    return null;
  }

  Future<void> submit() async {
    final validation = validate();
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/api/v1/reseller/keys/request',
        data: {
          'quantity': requestedQuantity,
          'justification': justification.text.trim(),
          'tier': _tier,
        },
      );
      await widget.onSubmitted();
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Key request submitted for admin approval');
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _DialogShell(
    icon: Icons.add_card_outlined,
    title: 'Request keys from admin',
    subtitle: 'Approved quota lands in your stock instantly.',
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: busy ? null : submit,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_outlined),
        label: Text(busy ? 'Submitting…' : 'Submit request'),
      ),
    ],
    child: ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(false),
        trackVisibility: const WidgetStatePropertyAll(false),
        thickness: const WidgetStatePropertyAll(0),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuotaStrip(
            monthlyQuota: monthlyQuota,
            usedKeys: usedKeys,
            remainingQuota: remainingQuota,
            maxPerRequest: maxPerRequest,
          ),
          const SizedBox(height: 18),
          // ── Tier selection ───────────────────────────────────────────
          const Text(
            'Key tier',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTone.ink,
            ),
          ),
          const SizedBox(height: 8),
          _TierOption(
            tier: 'standard',
            count: 0,
            quantity: requestedQuantity,
            selected: _tier == 'standard',
            onTap: () => setState(() => _tier = 'standard'),
            alwaysEnabled: true,
          ),
          const SizedBox(height: 8),
          _TierOption(
            tier: 'premium',
            count: 0,
            quantity: requestedQuantity,
            selected: _tier == 'premium',
            onTap: () => setState(() => _tier = 'premium'),
            alwaysEnabled: true,
          ),
          const SizedBox(height: 8),
          _TierOption(
            tier: 'vip',
            count: 0,
            quantity: requestedQuantity,
            selected: _tier == 'vip',
            onTap: () => setState(() => _tier = 'vip'),
            alwaysEnabled: true,
          ),
          const SizedBox(height: 18),
          // ── Quantity ─────────────────────────────────────────────────
          QuantityStepper(
            controller: quantity,
            label: 'Quantity',
            min: 1,
            max: maxPerRequest,
            onChanged: () => setState(() => error = null),
          ),
          const SizedBox(height: 14),
          // ── Justification ─────────────────────────────────────────────
          TextField(
            controller: justification,
            maxLines: 3,
            onChanged: (_) => setState(() => error = null),
            decoration: InputDecoration(
              labelText: 'Justification for admin',
              alignLabelWithHint: true,
              prefixIcon: const Icon(Icons.notes_outlined),
              filled: true,
              fillColor: AppTone.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _RequestPreview(
            quantity: requestedQuantity <= 0 ? 0 : requestedQuantity,
            remainingAfter: (remainingQuota - requestedQuantity).clamp(0, remainingQuota),
          ),
          AnimatedSize(
            duration: _medium,
            child: error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _InlineNotice(
                      message: error!,
                      tone: AppTone.red,
                      icon: Icons.error_outline,
                    ),
                  ),
          ),
        ],
      ),
    ),
    ),
    ),
  );
}

class _QuotaStrip extends StatelessWidget {
  const _QuotaStrip({
    required this.monthlyQuota,
    required this.usedKeys,
    required this.remainingQuota,
    required this.maxPerRequest,
  });
  final int monthlyQuota;
  final int usedKeys;
  final int remainingQuota;
  final int maxPerRequest;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MiniFact(label: 'Monthly quota', value: '$monthlyQuota'),
        _MiniFact(label: 'Used', value: '$usedKeys'),
        _MiniFact(label: 'Remaining', value: '$remainingQuota'),
        _MiniFact(label: 'Max request', value: '$maxPerRequest'),
      ],
    );
  }
}

class _RequestPreview extends StatelessWidget {
  const _RequestPreview({required this.quantity, required this.remainingAfter});
  final int quantity;
  final int remainingAfter;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Row(
        children: [
          const Icon(Icons.rule_folder_outlined, color: AppTone.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$quantity keys will be sent to admin approval. Estimated quota after approval: $remainingAfter.',
              style: const TextStyle(
                color: AppTone.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssignKeysDialog extends StatefulWidget {
  const AssignKeysDialog({
    super.key,
    required this.api,
    required this.dealerId,
    this.dealerName,
    this.availableCount,
    this.onAssigned,
  });
  final ApiClient api;
  final String dealerId;
  final String? dealerName;
  final int? availableCount;
  final Future<void> Function()? onAssigned;

  @override
  State<AssignKeysDialog> createState() => _AssignKeysDialogState();
}

class _AssignKeysDialogState extends State<AssignKeysDialog> {
  final _qty = TextEditingController(text: '1');
  String _tier = 'standard';
  String? error;
  bool busy = false;

  int get _quantity => int.tryParse(_qty.text.trim()) ?? 0;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _loadQuota() async {
    final q = asMap((await widget.api.get('/api/v1/reseller/quota')).data);
    return {
      'standard': (q['quota_standard'] as num?)?.toInt() ?? 0,
      'premium':  (q['quota_premium']  as num?)?.toInt() ?? 0,
      'vip':      (q['quota_vip']      as num?)?.toInt() ?? 0,
    };
  }

  Future<void> _submit(Map<String, int> quota) async {
    final avail = quota[_tier] ?? 0;
    if (_quantity <= 0) { setState(() => error = 'Enter a valid quantity.'); return; }
    if (_quantity > avail) {
      setState(() => error = 'Only $avail $_tierLabel keys available.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      await widget.api.post(
        '/api/v1/reseller/dealers/${widget.dealerId}/assign-keys',
        data: {'quantity': _quantity, 'tier': _tier},
      );
      await widget.onAssigned?.call();
      if (mounted) { Navigator.pop(context); snack(context, '$_quantity $_tierLabel keys sent'); }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get _tierLabel => _tier == 'vip' ? 'VIP' : _tier == 'premium' ? 'Premium' : 'Standard';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _loadQuota(),
      builder: (context, snapshot) {
        final quota   = snapshot.data ?? const {'standard': 0, 'premium': 0, 'vip': 0};
        final avail   = quota[_tier] ?? 0;
        final loading = snapshot.connectionState != ConnectionState.done;
        return _DialogShell(
          icon: Icons.outgoing_mail,
          title: 'Assign keys',
          subtitle: 'Send keys to ${widget.dealerName ?? 'this dealer'}.',
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: busy || loading ? null : () => _submit(quota),
              icon: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: Text(busy ? 'Sending…' : 'Send keys'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Tier selector ──────────────────────────────────────────
              const Text('Key tier', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final t in ['standard', 'premium', 'vip']) ...[
                    Expanded(
                      child: _TierOption(
                        tier: t,
                        count: quota[t] ?? 0,
                        quantity: _quantity,
                        selected: _tier == t,
                        onTap: () => setState(() { _tier = t; error = null; }),
                      ),
                    ),
                    if (t != 'vip') const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              // ── Quantity ───────────────────────────────────────────────
              QuantityStepper(
                controller: _qty,
                label: 'Keys to send',
                min: 1,
                max: avail <= 0 ? 1 : avail,
                onChanged: () => setState(() => error = null),
              ),
              AnimatedSize(
                duration: _medium,
                child: error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _InlineNotice(message: error!, tone: AppTone.red, icon: Icons.error_outline),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Send Keys Wizard ──────────────────────────────────────────────────────

class _SendKeysWizard extends StatefulWidget {
  const _SendKeysWizard({
    required this.api,
    required this.dealers,
    required this.tierQuota,
    required this.onAssigned,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> dealers;
  final Map<String, int> tierQuota;
  final Future<void> Function() onAssigned;

  @override
  State<_SendKeysWizard> createState() => _SendKeysWizardState();
}

class _SendKeysWizardState extends State<_SendKeysWizard>
    with SingleTickerProviderStateMixin {
  int _step = 0;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  String? _selectedDealerId;
  final _quantityController = TextEditingController(text: '1');
  int get _quantity => int.tryParse(_quantityController.text.trim()) ?? 1;

  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _holdComplete = false;
  bool _apiBusy = false;
  bool _apiSuccess = false;
  Object? _apiError;

  String _selectedTier = 'standard';
  int get _availableCount => _tierCount(_selectedTier);
  int _tierCount(String t) => widget.tierQuota[t] ?? 0;
  String get _tierLabel => switch (_selectedTier) {
        'premium' => 'Premium',
        'vip' => 'VIP',
        _ => 'Standard',
      };

  Map<String, dynamic>? get _selectedDealer {
    for (final d in widget.dealers) {
      if (dealerIdentifier(d) == _selectedDealerId) return d;
    }
    return null;
  }

  List<Map<String, dynamic>> get _filteredDealers {
    if (_searchQuery.isEmpty) return widget.dealers;
    final q = _searchQuery.toLowerCase();
    return widget.dealers.where((d) {
      return text(d['name']).toLowerCase().contains(q) ||
          text(d['business_name'] ?? d['shop_name']).toLowerCase().contains(q) ||
          text(d['phone']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _holdController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _onHoldStart(LongPressStartDetails _) {
    if (_apiBusy || _holdComplete) return;
    _holdController.forward(from: 0);
    _holdController.addStatusListener(_onHoldStatus);
    _fireApi();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _holdController.removeStatusListener(_onHoldStatus);
      setState(() => _holdComplete = true);
      _checkBothDone();
    }
  }

  Future<void> _fireApi() async {
    setState(() {
      _apiBusy = true;
      _apiError = null;
    });
    try {
      await widget.api.post(
        '/api/v1/reseller/dealers/$_selectedDealerId/assign-keys',
        data: {'quantity': _quantity, 'tier': _selectedTier},
      );
      if (mounted) {
        setState(() {
          _apiSuccess = true;
          _apiBusy = false;
        });
        _checkBothDone();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiError = e;
          _apiBusy = false;
          _holdComplete = false;
        });
        _holdController.removeStatusListener(_onHoldStatus);
        _holdController.reverse();
      }
    }
  }

  void _checkBothDone() {
    if (_holdComplete && _apiSuccess) {
      setState(() => _step = 5);
      widget.onAssigned();
    }
  }

  void _onHoldCancel() {
    if (!_holdComplete) _holdController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _WizardStepIndicator(step: _step, total: 6),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: AnimatedSwitcher(
                duration: _medium,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _stepContent(),
                ),
              ),
            ),
          ),
          _stepActions(),
        ],
      ),
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep3(); // tier first
      case 3:
        return _buildStep2(); // quantity second (max now uses selected tier)
      case 4:
        return _buildStep4();
      case 5:
        return _buildStep5();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: switch (_step) {
        0 => const SizedBox.shrink(),
        1 => Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Confirm dealer'),
            ),
          ],
        ),
        2 => Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _step = 1),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 3),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Set quantity'),
            ),
          ],
        ),
        3 => Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _quantity >= 1 && _quantity <= _availableCount
                  ? () => setState(() => _step = 4)
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Review'),
            ),
          ],
        ),
        4 => Row(
          children: [
            TextButton.icon(
              onPressed: _apiBusy
                  ? null
                  : () {
                      _holdController.reset();
                      _holdController.removeStatusListener(_onHoldStatus);
                      setState(() {
                        _step = 3;
                        _holdComplete = false;
                        _apiSuccess = false;
                        _apiError = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ],
        ),
        5 => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('View Dealer'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  // ── Step 0: Select Dealer ──────────────────────────────────────────────────

  Widget _buildStep0() {
    final dealers = _filteredDealers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a dealer',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select who receives the keys',
          style: TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: _fast,
          decoration: BoxDecoration(
            color: AppTone.page,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _searchFocus.hasFocus ? AppTone.accent : AppTone.line,
              width: _searchFocus.hasFocus ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: const InputDecoration(
              hintText: 'Search by name, shop, phone…',
              prefixIcon: Icon(Icons.search),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(height: 12),
        if (dealers.isEmpty)
          _InlineNotice(
            message: _searchQuery.isEmpty
                ? 'No dealers found. Create a dealer first.'
                : 'No dealers match your search.',
            tone: AppTone.muted,
            icon: Icons.search_off,
          )
        else
          ...dealers.asMap().entries.map((entry) {
            final i = entry.key;
            final dealer = entry.value;
            final id = dealerIdentifier(dealer);
            final name = text(dealer['name'], fallback: 'Dealer');
            final initials = name.length >= 2
                ? name.substring(0, 2).toUpperCase()
                : name.substring(0, 1).toUpperCase();
            final shop = text(
              dealer['business_name'] ?? dealer['shop_name'],
              fallback: '',
            );
            final phone = text(dealer['phone'], fallback: '');
            final status = text(dealer['status'], fallback: 'active');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() => _selectedDealerId = id);
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted) setState(() => _step = 1);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _selectedDealerId == id
                        ? AppTone.accentLight
                        : AppTone.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _selectedDealerId == id
                          ? AppTone.accent
                          : AppTone.line,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTone.accent, AppTone.brand],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            if (shop.isNotEmpty)
                              Text(
                                shop,
                                style: const TextStyle(
                                  color: AppTone.muted,
                                  fontSize: 13,
                                ),
                              ),
                            if (phone.isNotEmpty)
                              Text(
                                phone,
                                style: const TextStyle(
                                  color: AppTone.muted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(
                        label: status,
                        color: statusColor(status),
                      ),
                    ],
                  ),
                ),
              )
                  .animate(delay: (30 * i).ms)
                  .fadeIn(duration: 180.ms)
                  .slideY(begin: 0.03, end: 0),
            );
          }),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 1: Verify Dealer ──────────────────────────────────────────────────

  Widget _buildStep1() {
    final dealer = _selectedDealer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Confirm dealer',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Review before sending keys',
          style: TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 20),
        _DealerPreview(dealer: dealer),
        const SizedBox(height: 14),
        const _InlineNotice(
          message:
              'Once sent, keys are immediately available to this dealer. '
              'This action cannot be undone.',
          tone: AppTone.warning,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 2: Select Quantity ────────────────────────────────────────────────

  Widget _buildStep2() {
    final dealer = _selectedDealer!;
    final name = text(dealer['name'], fallback: 'Dealer');
    final qty = _quantity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Set quantity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'How many keys to send',
          style: TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTone.brandLight,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTone.brand.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront, color: AppTone.brand, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTone.brand,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _InlineNotice(
          message: '$_availableCount $_tierLabel keys available in quota.',
          tone: AppTone.info,
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 20),
        _LargeQuantityStepper(
          controller: _quantityController,
          min: 1,
          max: _availableCount <= 0 ? 1 : _availableCount,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 25, 50, 100]
              .where((v) => v <= _availableCount)
              .map(
                (v) => ActionChip(
                  label: Text('$v'),
                  onPressed: () {
                    _quantityController.text = '$v';
                    setState(() {});
                  },
                  backgroundColor: qty == v
                      ? AppTone.accent.withValues(alpha: 0.12)
                      : null,
                  side: qty == v
                      ? const BorderSide(color: AppTone.accent)
                      : const BorderSide(color: AppTone.line),
                  labelStyle: TextStyle(
                    color: qty == v ? AppTone.accent : AppTone.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: _fast,
          child: Text(
            key: ValueKey(_quantity),
            'Dealer will receive $_quantity activation '
            '${_quantity == 1 ? 'code' : 'codes'} immediately.',
            style: const TextStyle(
              color: AppTone.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 3: Select Tier ────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select key tier',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose which type of keys to send',
          style: TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 20),
        _TierOption(
          tier: 'standard',
          count: _tierCount('standard'),
          quantity: _quantity,
          selected: _selectedTier == 'standard',
          onTap: () => setState(() => _selectedTier = 'standard'),
        ),
        const SizedBox(height: 10),
        _TierOption(
          tier: 'premium',
          count: _tierCount('premium'),
          quantity: _quantity,
          selected: _selectedTier == 'premium',
          onTap: () => setState(() => _selectedTier = 'premium'),
        ),
        const SizedBox(height: 10),
        _TierOption(
          tier: 'vip',
          count: _tierCount('vip'),
          quantity: _quantity,
          selected: _selectedTier == 'vip',
          onTap: () => setState(() => _selectedTier = 'vip'),
        ),
        const SizedBox(height: 16),
        AnimatedSize(
          duration: _fast,
          child: _tierCount(_selectedTier) < _quantity
              ? _InlineNotice(
                  message:
                      'Only ${_tierCount(_selectedTier)} $_tierLabel keys in '
                      'stock. Reduce quantity or choose a different tier.',
                  tone: AppTone.warning,
                  icon: Icons.warning_amber_rounded,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 4: Hold to Confirm ────────────────────────────────────────────────

  Widget _buildStep4() {
    final dealer = _selectedDealer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hold to confirm',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'This action is irreversible',
          style: TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 20),
        _SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                'Dealer',
                text(dealer['name'], fallback: 'Dealer'),
              ),
              const SizedBox(height: 6),
              _InfoRow('Tier', _tierLabel),
              const SizedBox(height: 6),
              _InfoRow('Keys', '$_quantity activation codes'),
              const SizedBox(height: 6),
              _InfoRow(
                'Stock after',
                '${_availableCount - _quantity} remaining',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _InlineNotice(
          message:
              'Hold the button below for 1.5 seconds to send keys. '
              'This cannot be reversed.',
          tone: AppTone.warning,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 24),
        Center(
          child: AnimatedBuilder(
            animation: _holdController,
            builder: (context, _) {
              final progress = _holdController.value;
              final color = _apiBusy
                  ? AppTone.brand
                  : Color.lerp(AppTone.warning, AppTone.brand, progress)!;
              return GestureDetector(
                onLongPressStart: _apiBusy || _holdComplete ? null : _onHoldStart,
                onLongPressEnd: (_) => _onHoldCancel(),
                onLongPressCancel: _onHoldCancel,
                child: SizedBox(
                  width: 112,
                  height: 112,
                  child: CustomPaint(
                    painter: _ArcHoldPainter(
                      progress: progress,
                      trackColor: AppTone.warning.withValues(alpha: 0.15),
                      arcColor: color,
                      strokeWidth: 5,
                    ),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: progress > 0 ? 76 : 80,
                        height: progress > 0 ? 76 : 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.1),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: _apiBusy
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: color,
                                  ),
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      progress >= 1
                                          ? Icons.check_rounded
                                          : Icons.send_rounded,
                                      color: color,
                                      size: 26,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      progress == 0 ? 'Hold' : '${(progress * 100).toInt()}%',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Hold to send',
            style: TextStyle(
              color: AppTone.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        AnimatedSize(
          duration: _medium,
          child: _apiError == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InlineNotice(
                    message: readableError(_apiError),
                    tone: AppTone.danger,
                    icon: Icons.error_outline,
                  ),
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 5: Success ────────────────────────────────────────────────────────

  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => CustomPaint(
              size: const Size(96, 96),
              painter: _SuccessCirclePainter(progress: value),
              child: child,
            ),
            child: SizedBox(
              width: 96,
              height: 96,
              child: Center(
                child: const Icon(
                  Icons.check_rounded,
                  color: AppTone.brand,
                  size: 44,
                )
                    .animate(delay: 600.ms)
                    .scale(
                      begin: const Offset(0, 0),
                      end: const Offset(1, 1),
                      curve: Curves.elasticOut,
                      duration: 500.ms,
                    )
                    .fadeIn(duration: 200.ms),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => CustomPaint(
              size: const Size(200, 100),
              painter: _ConfettiBurstPainter(progress: v),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Keys Sent!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppTone.ink,
          ),
        )
            .animate(delay: 400.ms)
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.1, end: 0),
        const SizedBox(height: 8),
        Text(
          '$_quantity ${_quantity == 1 ? 'key' : 'keys'} sent to '
          '${text(_selectedDealer?['name'], fallback: 'dealer')}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTone.muted, fontSize: 15),
        ).animate(delay: 550.ms).fadeIn(),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ─── Wizard Helper Widgets ──────────────────────────────────────────────────

class _TierOption extends StatelessWidget {
  const _TierOption({
    required this.tier,
    required this.count,
    required this.quantity,
    required this.selected,
    required this.onTap,
    this.alwaysEnabled = false,
  });
  final String tier;
  final int count;
  final int quantity;
  final bool selected;
  final VoidCallback onTap;
  final bool alwaysEnabled;

  @override
  Widget build(BuildContext context) {
    final (label, icon, grad) = switch (tier) {
      'premium' => (
        'Premium',
        Icons.star_rounded,
        [const Color(0xFF1D4ED8), const Color(0xFF60A5FA)],
      ),
      'vip' => (
        'VIP',
        Icons.diamond_rounded,
        [const Color(0xFF7C3AED), const Color(0xFFD97706)],
      ),
      _ => (
        'Standard',
        Icons.key_rounded,
        [const Color(0xFF6B7280), const Color(0xFF9CA3AF)],
      ),
    };

    final enough = alwaysEnabled || count >= quantity;
    final disabled = !alwaysEnabled && count == 0;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: grad
                      .map((c) => c.withValues(alpha: 0.12))
                      .toList(),
                )
              : null,
          color: selected ? null : AppTone.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? grad[0] : AppTone.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: disabled
                      ? [AppTone.muted.withValues(alpha: 0.4),
                         AppTone.muted.withValues(alpha: 0.2)]
                      : grad,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: disabled ? AppTone.muted : AppTone.ink,
                    ),
                  ),
                  Text(
                    disabled
                        ? 'Out of stock'
                        : !enough
                            ? '$count available — need $quantity'
                            : '$count keys available',
                    style: TextStyle(
                      color: !enough && !disabled
                          ? AppTone.warning
                          : AppTone.muted,
                      fontSize: 13,
                      fontWeight: !enough && !disabled
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              Icon(Icons.check_circle_rounded, color: grad[0])
            else
              Icon(
                Icons.radio_button_unchecked,
                color: disabled ? AppTone.muted.withValues(alpha: 0.4) : AppTone.line,
              ),
          ],
        ),
      ),
    );
  }
}

class _WizardStepIndicator extends StatelessWidget {
  const _WizardStepIndicator({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i == step;
          final done = i < step;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedContainer(
              duration: _fast,
              width: active ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: done
                    ? AppTone.brand
                    : active
                        ? AppTone.accent
                        : AppTone.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _LargeQuantityStepper extends StatelessWidget {
  const _LargeQuantityStepper({
    required this.controller,
    required this.min,
    required this.max,
    this.onChanged,
  });
  final TextEditingController controller;
  final int min;
  final int max;
  final VoidCallback? onChanged;

  int get current => int.tryParse(controller.text.trim()) ?? min;
  int get effectiveMax => max < min ? min : max;

  void setQuantity(int value) {
    final next = value.clamp(min, effectiveMax).toInt();
    controller.text = '$next';
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final value = current;
    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton(
            onPressed: value <= min ? null : () => setQuantity(value - 1),
            icon: const Icon(Icons.remove, size: 26),
            style: IconButton.styleFrom(
              foregroundColor: AppTone.ink,
              backgroundColor: AppTone.page,
              side: const BorderSide(color: AppTone.line),
              shape: const CircleBorder(),
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppTone.ink,
                ),
                textAlign: TextAlign.center,
              ),
              const Text(
                'keys',
                style: TextStyle(color: AppTone.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 56,
          height: 56,
          child: IconButton(
            onPressed: value >= effectiveMax ? null : () => setQuantity(value + 1),
            icon: const Icon(Icons.add, size: 26),
            style: IconButton.styleFrom(
              foregroundColor: AppTone.surface,
              backgroundColor: AppTone.accent,
              disabledBackgroundColor: AppTone.accent.withValues(alpha: 0.3),
              shape: const CircleBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTone.muted, fontSize: 13),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _ArcHoldPainter extends CustomPainter {
  const _ArcHoldPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
    this.strokeWidth = 5,
  });
  final double progress;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - strokeWidth / 2;
    final rect   = Rect.fromCircle(center: center, radius: radius);
    final paint  = Paint()
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round
      ..strokeWidth = strokeWidth;

    // Track ring
    paint.color = trackColor;
    canvas.drawCircle(center, radius, paint);

    // Arc sweep — clockwise from top (-π/2)
    if (progress > 0) {
      paint.color = arcColor;
      canvas.drawArc(rect, -pi / 2, 2 * pi * progress, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcHoldPainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}

class _SuccessCirclePainter extends CustomPainter {
  const _SuccessCirclePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTone.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 4,
    );
    canvas.drawArc(rect, -pi / 2, 2 * pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(_SuccessCirclePainter old) => old.progress != progress;
}

class _ConfettiBurstPainter extends CustomPainter {
  const _ConfettiBurstPainter({required this.progress});
  final double progress;
  static const _colors = [
    AppTone.brand,
    AppTone.accent,
    AppTone.warning,
    AppTone.info,
  ];
  static const _count = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < _count; i++) {
      final angle = i * (2 * pi / _count) + pi / 8;
      final paint = Paint()
        ..color = _colors[i % 4].withValues(
          alpha: (1 - progress).clamp(0.0, 1.0),
        );
      final offset = Offset(
        center.dx + cos(angle) * 60 * progress,
        center.dy + sin(angle) * 60 * progress,
      );
      canvas.drawCircle(offset, 4, paint);
    }
  }

  @override
  bool shouldRepaint(_ConfettiBurstPainter old) => old.progress != progress;
}

class _DealerPreview extends StatelessWidget {
  const _DealerPreview({required this.dealer});
  final Map<String, dynamic> dealer;

  @override
  Widget build(BuildContext context) {
    return _InfoTile(
      icon: Icons.storefront,
      color: AppTone.blue,
      title: text(dealer['name'], fallback: 'Dealer'),
      subtitle:
          '${text(dealer['email'], fallback: 'No email')}\n${text(dealer['business_name'] ?? dealer['shop_name'], fallback: 'No shop name')}',
      trailing: StatusPill(
        label: text(dealer['status'], fallback: 'active'),
        color: statusColor(text(dealer['status'], fallback: 'active')),
      ),
    );
  }
}

// ── Create Dealer Wizard ─────────────────────────────────────────────────────

// District → Division mapping for Bangladesh
const _districtDivision = <String, String>{
  'Dhaka': 'Dhaka', 'Gazipur': 'Dhaka', 'Narayanganj': 'Dhaka',
  'Narsingdi': 'Dhaka', 'Manikganj': 'Dhaka', 'Munshiganj': 'Dhaka',
  'Tangail': 'Dhaka', 'Kishoreganj': 'Dhaka', 'Rajbari': 'Dhaka',
  'Faridpur': 'Dhaka', 'Madaripur': 'Dhaka', 'Shariatpur': 'Dhaka',
  'Gopalganj': 'Dhaka',
  'Chittagong': 'Chittagong', "Cox's Bazar": 'Chittagong',
  'Noakhali': 'Chittagong', 'Feni': 'Chittagong', 'Lakshmipur': 'Chittagong',
  'Chandpur': 'Chittagong', 'Comilla': 'Chittagong', 'Brahmanbaria': 'Chittagong',
  'Bandarban': 'Chittagong', 'Rangamati': 'Chittagong', 'Khagrachhari': 'Chittagong',
  'Rajshahi': 'Rajshahi', 'Bogura': 'Rajshahi', 'Joypurhat': 'Rajshahi',
  'Naogaon': 'Rajshahi', 'Natore': 'Rajshahi', 'Chapai Nawabganj': 'Rajshahi',
  'Pabna': 'Rajshahi', 'Sirajganj': 'Rajshahi',
  'Khulna': 'Khulna', 'Jessore': 'Khulna', 'Satkhira': 'Khulna',
  'Bagerhat': 'Khulna', 'Narail': 'Khulna', 'Magura': 'Khulna',
  'Jhenaidah': 'Khulna', 'Kushtia': 'Khulna', 'Meherpur': 'Khulna',
  'Chuadanga': 'Khulna',
  'Barishal': 'Barishal', 'Patuakhali': 'Barishal', 'Bhola': 'Barishal',
  'Pirojpur': 'Barishal', 'Jhalokati': 'Barishal', 'Barguna': 'Barishal',
  'Sylhet': 'Sylhet', 'Habiganj': 'Sylhet', 'Moulvibazar': 'Sylhet',
  'Sunamganj': 'Sylhet',
  'Rangpur': 'Rangpur', 'Dinajpur': 'Rangpur', 'Gaibandha': 'Rangpur',
  'Kurigram': 'Rangpur', 'Lalmonirhat': 'Rangpur', 'Nilphamari': 'Rangpur',
  'Panchagarh': 'Rangpur', 'Thakurgaon': 'Rangpur',
  'Mymensingh': 'Mymensingh', 'Jamalpur': 'Mymensingh',
  'Netrokona': 'Mymensingh', 'Sherpur': 'Mymensingh',
};

class _CreateDealerWizard extends StatefulWidget {
  const _CreateDealerWizard({required this.api, required this.onCreated});
  final ApiClient api;
  final Future<void> Function() onCreated;

  @override
  State<_CreateDealerWizard> createState() => _CreateDealerWizardState();
}

class _CreateDealerWizardState extends State<_CreateDealerWizard> {
  int _step = 0;

  // Step 0 — Identity
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();

  // Step 1 — Business
  final _shopCtrl     = TextEditingController();
  final _bizCtrl      = TextEditingController();

  // Step 2 — Address (Google Maps style)
  final _streetCtrl   = TextEditingController(); // house/road/area
  final _thanaCtrl    = TextEditingController(); // upazila/thana
  String? _district;
  String? _division; // auto-populated from district

  // Step 3 — Documents
  final _licenseCtrl  = TextEditingController();
  final _nidCtrl      = TextEditingController();

  // Dealer photo
  XFile? _photo;

  // Step 3 — Password
  final _pwCtrl       = TextEditingController();
  final _pwConfCtrl   = TextEditingController();
  bool _showPw        = false;
  bool _showPwConf    = false;

  // Step 4 — Submit
  bool _busy          = false;
  Object? _error;

  String? _step0Error;
  String? _step3Error;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _emailCtrl, _shopCtrl, _bizCtrl,
        _streetCtrl, _thanaCtrl, _licenseCtrl, _nidCtrl, _pwCtrl, _pwConfCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validateStep0() {
    final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (_nameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        !emailRe.hasMatch(_emailCtrl.text.trim())) {
      setState(() => _step0Error = 'Name, valid email and phone are required');
      return false;
    }
    setState(() => _step0Error = null);
    return true;
  }

  bool _validateStep3() {
    if (_pwCtrl.text.length < 8) {
      setState(() => _step3Error = 'Password must be at least 8 characters');
      return false;
    }
    if (_pwCtrl.text != _pwConfCtrl.text) {
      setState(() => _step3Error = 'Passwords do not match');
      return false;
    }
    setState(() => _step3Error = null);
    return true;
  }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      String? photoUrl;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        final b64 = base64Encode(bytes);
        final ext = _photo!.name.split('.').last.toLowerCase();
        photoUrl = 'data:image/$ext;base64,$b64';
      }

      await widget.api.post(
        '/api/v1/reseller/dealers',
        data: {
          'name':         _nameCtrl.text.trim(),
          'email':        _emailCtrl.text.trim(),
          'phone':        _phoneCtrl.text.trim(),
          'shopName':     _shopCtrl.text.trim(),
          'businessName': _bizCtrl.text.trim(),
          'address':      _streetCtrl.text.trim(),
          'thana':        _thanaCtrl.text.trim(),
          'district':     _district,
          'division':     _division,
          'tradeLicense': _licenseCtrl.text.trim(),
          'nid':          _nidCtrl.text.trim(),
          'photoUrl':     photoUrl,
          'password':     _pwCtrl.text,
        },
      );
      if (mounted) {
        setState(() => _step = 5);
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _WizardStepIndicator(step: _step.clamp(0, 5), total: 6),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: AnimatedSwitcher(
                duration: _medium,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
          ),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildStep() {
    return switch (_step) {
      0 => _stepIdentity(),
      1 => _stepBusiness(),
      2 => _stepAddress(),
      3 => _stepDocuments(),
      4 => _stepPassword(),
      5 => _stepReview(),
      _ => _stepDone(),
    };
  }

  // ── Step 0: Identity ──────────────────────────────────────────────────────

  Widget _stepIdentity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Dealer identity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Basic contact info and photo',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      // Photo picker
      Center(
        child: GestureDetector(
          onTap: () async {
            final picker = ImagePicker();
            final picked = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 800,
              imageQuality: 80,
            );
            if (picked != null) setState(() => _photo = picked);
          },
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: AppTone.accentLight,
                backgroundImage: _photo != null
                    ? FileImage(File(_photo!.path))
                    : null,
                child: _photo == null
                    ? const Icon(Icons.person, size: 40, color: AppTone.accent)
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTone.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Center(
        child: Text('Tap to add photo',
            style: TextStyle(color: AppTone.muted, fontSize: 12)),
      ),
      const SizedBox(height: 20),
      _WizardField(label: 'Full name', controller: _nameCtrl,
          hint: 'e.g. Karim Traders', icon: Icons.person_outline),
      const SizedBox(height: 12),
      _WizardField(label: 'Phone number', controller: _phoneCtrl,
          hint: '01XXXXXXXXX', icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone),
      const SizedBox(height: 12),
      _WizardField(label: 'Email address', controller: _emailCtrl,
          hint: 'dealer@example.com', icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress),
      if (_step0Error != null) ...[
        const SizedBox(height: 8),
        Text(_step0Error!, style: const TextStyle(color: AppTone.danger, fontSize: 13)),
      ],
      const SizedBox(height: 20),
    ],
  );

  // ── Step 1: Business ──────────────────────────────────────────────────────

  Widget _stepBusiness() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Business details',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Shop and business info',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      _WizardField(label: 'Shop name', controller: _shopCtrl,
          hint: 'e.g. Karim Mobile Shop', icon: Icons.storefront_outlined),
      const SizedBox(height: 12),
      _WizardField(label: 'Business name (optional)', controller: _bizCtrl,
          hint: 'Registered business name', icon: Icons.business_outlined),
      const SizedBox(height: 20),
    ],
  );

  // ── Step 2: Address ───────────────────────────────────────────────────────

  Widget _stepAddress() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Location',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Full address — will be used for map integration',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      _WizardField(
        label: 'House / Road / Area',
        controller: _streetCtrl,
        hint: 'e.g. House 12, Road 5, Mirpur-10',
        icon: Icons.signpost_outlined,
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      _WizardField(
        label: 'Thana / Upazila',
        controller: _thanaCtrl,
        hint: 'e.g. Mirpur, Gulshan, Dhanmondi',
        icon: Icons.location_city_outlined,
      ),
      const SizedBox(height: 12),
      _DistrictDropdown(
        value: _district,
        onChanged: (v) => setState(() {
          _district = v;
          _division = v != null ? _districtDivision[v] : null;
        }),
      ),
      const SizedBox(height: 12),
      // Division — auto-filled, read-only
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Division',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTone.ink)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTone.page,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTone.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, size: 20, color: AppTone.muted),
                const SizedBox(width: 12),
                Text(
                  _division ?? 'Auto-filled from district',
                  style: TextStyle(
                    color: _division != null ? AppTone.ink : AppTone.muted,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const _InlineNotice(
        message: 'Map pin will be added in a future update. Address is saved for now.',
        tone: AppTone.info,
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 20),
    ],
  );

  // ── Step 3: Documents ─────────────────────────────────────────────────────

  Widget _stepDocuments() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Identity documents',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('NID and trade license',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      _WizardField(
        label: 'NID number',
        controller: _nidCtrl,
        hint: 'National ID card number',
        icon: Icons.credit_card_outlined,
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      _WizardField(
        label: 'Trade license number (optional)',
        controller: _licenseCtrl,
        hint: 'e.g. TL-2024-XXXXXX',
        icon: Icons.badge_outlined,
      ),
      const SizedBox(height: 12),
      const _InlineNotice(
        message: 'Documents can be updated later from the dealer profile.',
        tone: AppTone.info,
        icon: Icons.info_outline,
      ),
      const SizedBox(height: 20),
    ],
  );

  // ── Step 3: Password ──────────────────────────────────────────────────────

  Widget _stepPassword() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Set access password',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Tell this password to the dealer in person',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      _WizardField(
        label: 'Temporary password', controller: _pwCtrl,
        hint: 'At least 8 characters', icon: Icons.lock_outline,
        obscure: !_showPw,
        suffixIcon: IconButton(
          icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility,
              color: AppTone.muted),
          onPressed: () => setState(() => _showPw = !_showPw),
        ),
      ),
      const SizedBox(height: 12),
      _WizardField(
        label: 'Confirm password', controller: _pwConfCtrl,
        hint: 'Repeat password', icon: Icons.lock_outline,
        obscure: !_showPwConf,
        suffixIcon: IconButton(
          icon: Icon(_showPwConf ? Icons.visibility_off : Icons.visibility,
              color: AppTone.muted),
          onPressed: () => setState(() => _showPwConf = !_showPwConf),
        ),
      ),
      if (_step3Error != null) ...[
        const SizedBox(height: 8),
        Text(_step3Error!, style: const TextStyle(color: AppTone.danger, fontSize: 13)),
      ],
      const SizedBox(height: 12),
      const _InlineNotice(
        message: 'The dealer will log in with their email and this password. '
            'They can change it after first login.',
        tone: AppTone.warning,
        icon: Icons.warning_amber_rounded,
      ),
      const SizedBox(height: 20),
    ],
  );

  // ── Step 4: Review ────────────────────────────────────────────────────────

  Widget _stepReview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Review & confirm',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('Check everything before creating the account',
          style: TextStyle(color: AppTone.muted)),
      const SizedBox(height: 20),
      Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppTone.accentLight,
            backgroundImage: _photo != null ? FileImage(File(_photo!.path)) : null,
            child: _photo == null
                ? const Icon(Icons.person, color: AppTone.accent)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nameCtrl.text.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(_emailCtrl.text.trim(),
                    style: const TextStyle(color: AppTone.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _SoftPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewSection('Identity', [
              _InfoRow('Phone', _phoneCtrl.text.trim()),
              _InfoRow('NID',   _nidCtrl.text.trim().isEmpty ? '—' : _nidCtrl.text.trim()),
            ]),
            const Divider(height: 24),
            _ReviewSection('Business', [
              _InfoRow('Shop',     _shopCtrl.text.trim().isEmpty ? '—' : _shopCtrl.text.trim()),
              _InfoRow('Business', _bizCtrl.text.trim().isEmpty ? '—' : _bizCtrl.text.trim()),
              _InfoRow('License',  _licenseCtrl.text.trim().isEmpty ? '—' : _licenseCtrl.text.trim()),
            ]),
            const Divider(height: 24),
            _ReviewSection('Location', [
              _InfoRow('Area',     _streetCtrl.text.trim().isEmpty ? '—' : _streetCtrl.text.trim()),
              _InfoRow('Thana',    _thanaCtrl.text.trim().isEmpty ? '—' : _thanaCtrl.text.trim()),
              _InfoRow('District', _district ?? '—'),
              _InfoRow('Division', _division ?? '—'),
            ]),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _InlineNotice(
          message: readableError(_error),
          tone: AppTone.danger,
          icon: Icons.error_outline,
        ),
      ],
      const SizedBox(height: 20),
    ],
  );

  // ── Step 5: Done ──────────────────────────────────────────────────────────

  Widget _stepDone() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => CustomPaint(
            size: const Size(96, 96),
            painter: _SuccessCirclePainter(progress: value),
            child: child,
          ),
          child: SizedBox(
            width: 96,
            height: 96,
            child: Center(
              child: const Icon(Icons.check_rounded, color: AppTone.brand, size: 44)
                  .animate(delay: 600.ms)
                  .scale(begin: const Offset(0, 0), end: const Offset(1, 1),
                      curve: Curves.elasticOut, duration: 500.ms)
                  .fadeIn(duration: 200.ms),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '${_nameCtrl.text.trim()} is ready!',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1, end: 0),
      const SizedBox(height: 8),
      Text(
        'Dealer account created. Share the password with them in person.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTone.muted, fontSize: 14),
      ).animate(delay: 550.ms).fadeIn(),
      const SizedBox(height: 20),
    ],
  );

  // ── Actions bar ───────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: switch (_step) {
        0 => Row(children: [
            const Spacer(),
            FilledButton.icon(
              onPressed: () { if (_validateStep0()) setState(() => _step = 1); },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Business info'),
            ),
          ]),
        1 => Row(children: [
            TextButton.icon(onPressed: () => setState(() => _step = 0),
                icon: const Icon(Icons.arrow_back), label: const Text('Back')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Location'),
            ),
          ]),
        2 => Row(children: [
            TextButton.icon(onPressed: () => setState(() => _step = 1),
                icon: const Icon(Icons.arrow_back), label: const Text('Back')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 3),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Documents'),
            ),
          ]),
        3 => Row(children: [
            TextButton.icon(onPressed: () => setState(() => _step = 2),
                icon: const Icon(Icons.arrow_back), label: const Text('Back')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => setState(() => _step = 4),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Set password'),
            ),
          ]),
        4 => Row(children: [
            TextButton.icon(onPressed: () => setState(() => _step = 3),
                icon: const Icon(Icons.arrow_back), label: const Text('Back')),
            const Spacer(),
            FilledButton.icon(
              onPressed: () { if (_validateStep3()) setState(() => _step = 5); },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Review'),
            ),
          ]),
        5 => Row(children: [
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() { _step = 4; _error = null; }),
              icon: const Icon(Icons.arrow_back), label: const Text('Back'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add),
              label: Text(_busy ? 'Creating…' : 'Create dealer'),
            ),
          ]),
        _ => SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
      },
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _WizardField extends StatelessWidget {
  const _WizardField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffixIcon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppTone.ink)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          maxLines: obscure ? 1 : maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AppTone.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTone.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTone.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTone.accent, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _DistrictDropdown extends StatelessWidget {
  const _DistrictDropdown({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('District',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppTone.ink)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          hint: const Text('Select district'),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.map_outlined, size: 20),
            filled: true,
            fillColor: AppTone.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppTone.accent, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          items: (_districtDivision.keys.toList()..sort())
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTone.muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }
}

class DataPage<T> extends StatefulWidget {
  const DataPage({
    super.key,
    required this.title,
    required this.loader,
    required this.builder,
    this.dealerId,
    this.sseEvents = const [],
  });
  final String title;
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  /// When provided, a successful load syncs device/key data to LocalVault.
  final String? dealerId;
  /// SSE event types that should trigger an automatic reload.
  final List<String> sseEvents;

  @override
  State<DataPage<T>> createState() => _DataPageState<T>();
}

class _DataPageState<T> extends State<DataPage<T>> {
  late Future<T> future = widget.loader();
  T? _lastData; // kept so UI stays visible during background refresh
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.sseEvents.isEmpty) return;
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream == null) return;
    final events = Set<String>.from(widget.sseEvents);
    _sseSub = stream.listen((event) {
      if (mounted && events.contains(event.type)) _silentReload();
    });
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  // Manual pull-to-refresh — shows loading spinner
  Future<void> reload() async {
    final next = widget.loader();
    setState(() { future = next; });
    await next;
  }

  // SSE-triggered silent refresh — keeps current data visible, no spinner
  Future<void> _silentReload() async {
    final next = widget.loader();
    try {
      final result = await next;
      if (mounted) setState(() { _lastData = result; future = Future.value(result); });
    } catch (_) {
      // silently ignore — current data stays shown
    }
  }

  void _trySync(T data) {
    final dealerId = widget.dealerId;
    if (dealerId == null) return;
    final map = data is Map<String, dynamic> ? data : null;
    if (map == null) return;
    final devices = asList(map, 'devices');
    final keys = asList(map, 'keys');
    if (devices.isNotEmpty) LocalVault.syncDevices(dealerId, devices);
    if (keys.isNotEmpty) LocalVault.syncKeys(dealerId, keys);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // If we have previous data (SSE silent refresh), keep showing it
          if (_lastData != null) {
            return widget.builder(context, _lastData as T, reload);
          }
          return _LoadingPage(title: widget.title);
        }
        if (snapshot.hasError) {
          // Try to show cached vault data before showing the error page
          return FutureBuilder<VaultSnapshot?>(
            future: LocalVault.read(),
            builder: (context, vaultSnap) {
              if (vaultSnap.connectionState != ConnectionState.done) {
                return _LoadingPage(title: widget.title);
              }
              final vault = vaultSnap.data;
              if (vault != null && !vault.isEmpty) {
                // Build a synthetic data map from vault — only works for
                // pages that consume 'devices' or 'keys' keys.
                final syntheticData = <String, dynamic>{
                  'devices': vault.devices,
                  'keys': vault.keys,
                };
                return Stack(
                  children: [
                    widget.builder(
                      context,
                      syntheticData as T,
                      reload,
                    ),
                    const Positioned(
                      top: 0, left: 0, right: 0,
                      child: _OfflineBanner(),
                    ),
                  ],
                );
              }
              // No vault — show original error page
              return Page(
                title: widget.title,
                reload: reload,
                children: [
                  Section(
                    title: 'Could not load',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          readableError(snapshot.error),
                          style: const TextStyle(
                            color: AppTone.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Pull down to try again.',
                          style: TextStyle(
                            color: AppTone.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }
        // Successful load — sync to vault and cache for silent refresh
        _lastData = snapshot.data as T;
        _trySync(snapshot.data as T);
        return widget.builder(context, snapshot.data as T, reload);
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        color: AppTone.warning.withValues(alpha: 0.92),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: const [
            Icon(Icons.cloud_off_outlined, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Viewing cached data — changes require connectivity.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: _fast).slideY(begin: -0.5, end: 0, duration: _fast);
  }
}

class Page extends StatefulWidget {
  const Page({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.reload,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final Future<void> Function()? reload;

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> with SingleTickerProviderStateMixin {
  bool _refreshing = false;
  double _pullOffset = 0.0;
  late AnimationController _radarAnim;

  @override
  void initState() {
    super.initState();
    _radarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _radarAnim.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (_refreshing || widget.reload == null) return;
    setState(() => _refreshing = true);
    _radarAnim.repeat();
    try {
      await widget.reload!();
    } finally {
      _radarAnim.stop();
      _radarAnim.reset();
      if (mounted) setState(() { _refreshing = false; _pullOffset = 0; });
    }
  }

  bool _handleScroll(ScrollNotification n) {
    if (widget.reload == null || _refreshing) return false;
    if (n is OverscrollNotification && n.metrics.extentBefore < 1.0 && n.overscroll < 0) {
      setState(() {
        _pullOffset = (_pullOffset + (-n.overscroll) * 0.55).clamp(0.0, 110.0);
      });
    } else if (n is ScrollUpdateNotification && (n.scrollDelta ?? 0) > 0) {
      setState(() {
        _pullOffset = (_pullOffset - n.scrollDelta! * 0.5).clamp(0.0, 110.0);
      });
    } else if (n is ScrollEndNotification) {
      if (_pullOffset >= 80) {
        _onRefresh();
      } else {
        setState(() => _pullOffset = 0);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pageChildren = <Widget>[
      _ContentIntro(
        title: widget.title,
        subtitle: widget.subtitle,
        actions: widget.actions,
      ),
      const SizedBox(height: 14),
      ...widget.children.asMap().entries.expand(
        (entry) => [
          entry.value
              .animate(delay: (45 * entry.key).ms)
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.025, end: 0),
          const SizedBox(height: 14),
        ],
      ),
    ];

    final scrollable = LayoutBuilder(
      builder: (context, constraints) => NotificationListener<ScrollNotification>(
        onNotification: _handleScroll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth > 980 ? 28 : 16,
            max(
              constraints.maxWidth < 600 ? 72.0 : 18.0,
              _refreshing ? 94.0 : _pullOffset.clamp(0.0, 94.0),
            ),
            constraints.maxWidth > 980 ? 28 : 16,
            24,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: pageChildren,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.reload == null) return scrollable;

    return Stack(
      children: [
        scrollable,
        Positioned(
          top: 0, left: 0, right: 0,
          child: _RadarPullIndicator(
            pullProgress: (_pullOffset / 80.0).clamp(0.0, 1.0),
            refreshing: _refreshing,
            animation: _radarAnim,
          ),
        ),
      ],
    );
  }
}



// ─── Radar pull-to-refresh ─────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.sweepAngle,
    required this.pullProgress,
    required this.refreshing,
  });
  final double sweepAngle;
  final double pullProgress;
  final bool refreshing;

  static const _brand = Color(0xFF00A86B);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Dark fill
    canvas.drawCircle(c, r, Paint()
      ..color = const Color(0xFF0A1628)
      ..style = PaintingStyle.fill);

    // Concentric grid rings
    final ringP = Paint()
      ..color = _brand.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(c, r * i / 4, ringP);
    }

    // Cross lines
    final lineP = Paint()
      ..color = _brand.withValues(alpha: 0.08)
      ..strokeWidth = 0.7;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), lineP);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), lineP);

    if (pullProgress > 0.05 || refreshing) {
      // Trailing sweep arc
      const arcSpan = pi * 1.15;
      final sweepRect = Rect.fromCircle(center: c, radius: r);
      final arcP = Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: sweepAngle - arcSpan,
          endAngle: sweepAngle,
          colors: [
            Colors.transparent,
            _brand.withValues(alpha: 0.0),
            _brand.withValues(alpha: 0.18),
            _brand.withValues(alpha: 0.45),
          ],
          stops: const [0.0, 0.35, 0.7, 1.0],
        ).createShader(sweepRect)
        ..style = PaintingStyle.fill;
      canvas.drawArc(sweepRect, sweepAngle - arcSpan, arcSpan, true, arcP);

      // Sweep arm
      canvas.drawLine(
        c,
        Offset(c.dx + cos(sweepAngle) * r, c.dy + sin(sweepAngle) * r),
        Paint()
          ..color = _brand.withValues(alpha: 0.9)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center dot
    canvas.drawCircle(c, 2.5, Paint()..color = _brand);

    // Outer ring border
    canvas.drawCircle(c, r - 0.5, Paint()
      ..color = _brand.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweepAngle != sweepAngle ||
      old.pullProgress != pullProgress ||
      old.refreshing != refreshing;
}

class _RadarPullIndicator extends StatelessWidget {
  const _RadarPullIndicator({
    required this.pullProgress,
    required this.refreshing,
    required this.animation,
  });
  final double pullProgress;
  final bool refreshing;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    if (pullProgress <= 0 && !refreshing) return const SizedBox.shrink();
    final scale = refreshing
        ? 1.0
        : Curves.easeOutBack.transform(pullProgress.clamp(0.0, 1.0));
    final opacity = (refreshing ? 1.0 : pullProgress).clamp(0.0, 1.0);
    final sweepAngle = animation.value * 2 * pi - pi / 2;

    return Align(
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 76,
            height: 76,
            margin: const EdgeInsets.only(top: 10),
            child: CustomPaint(
              painter: _RadarPainter(
                sweepAngle: sweepAngle,
                pullProgress: pullProgress,
                refreshing: refreshing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Pulsing rings (login hero) ─────────────────────────────────────────────

class _PulsingRingsPainter extends CustomPainter {
  const _PulsingRingsPainter(this.t);
  final double t;
  static const _brand = Color(0xFF00A86B);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // 5 expanding rings, staggered
    for (int i = 0; i < 5; i++) {
      final phase = (t + i * 0.2) % 1.0;
      final r = maxR * (0.15 + phase * 0.85);
      final opacity = (1 - phase) * (1 - phase) * 0.38;
      canvas.drawCircle(c, r, Paint()
        ..color = _brand.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + (1 - phase) * 1.2);
    }

    // Inner glow
    canvas.drawCircle(c, maxR * 0.28, Paint()
      ..shader = RadialGradient(
        colors: [
          _brand.withValues(alpha: 0.22),
          _brand.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: maxR * 0.28)));

    // Center circle (hosts icon)
    canvas.drawCircle(c, maxR * 0.13, Paint()
      ..color = _brand.withValues(alpha: 0.13));
    canvas.drawCircle(c, maxR * 0.13, Paint()
      ..color = _brand.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_PulsingRingsPainter old) => old.t != t;
}

class _PulsingRingsWidget extends StatefulWidget {
  const _PulsingRingsWidget({this.size = 220});
  final double size;

  @override
  State<_PulsingRingsWidget> createState() => _PulsingRingsWidgetState();
}

class _PulsingRingsWidgetState extends State<_PulsingRingsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _PulsingRingsPainter(_ctrl.value),
            ),
            Icon(
              Icons.security_rounded,
              size: widget.size * 0.18,
              color: AppTone.brand.withValues(alpha: 0.9),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────

class _ContentIntro extends StatelessWidget {
  const _ContentIntro({
    required this.title,
    required this.actions,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTone.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppTone.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => _AnimatedSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppTone.emerald,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class StatCard {
  const StatCard(this.label, this.value, {this.color = AppTone.ink, this.icon});
  final String label;
  final dynamic value;
  final Color color;
  final IconData? icon;
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cards});
  final List<StatCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth > 1000
          ? 4
          : c.maxWidth > 640
          ? 3
          : 2;
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: c.maxWidth > 640 ? 2.35 : 1.45,
        children: cards
            .asMap()
            .entries
            .map(
              (entry) => _MetricCard(card: entry.value)
                  .animate(delay: (55 * entry.key).ms)
                  .fadeIn(duration: 320.ms)
                  .scale(
                    begin: const Offset(0.985, 0.985),
                    end: const Offset(1, 1),
                  ),
            )
            .toList(),
      );
    },
  );
}

class _MetricCard extends StatefulWidget {
  const _MetricCard({required this.card});
  final StatCard card;

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.card.color;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: _fast,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTone.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hovered ? color.withValues(alpha: 0.28) : AppTone.line,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: hovered ? 0.12 : 0.05),
              blurRadius: hovered ? 18 : 10,
              offset: Offset(0, hovered ? 8 : 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                widget.card.icon ?? iconForLabel(widget.card.label),
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: widget.card.value ?? 0),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => Text(
                        '$val',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: color == AppTone.ink ? AppTone.ink : color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.card.label,
                      style: const TextStyle(
                        color: AppTone.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryPipeline extends StatelessWidget {
  const InventoryPipeline({
    super.key,
    required this.requested,
    required this.approved,
    required this.available,
    required this.assigned,
    required this.activated,
  });
  final int requested;
  final int approved;
  final int available;
  final int assigned;
  final int activated;

  @override
  Widget build(BuildContext context) {
    final items = [
      _PipelineItem('Requested', requested, Icons.pending_actions, AppTone.red),
      _PipelineItem(
        'Approved',
        approved,
        Icons.verified_outlined,
        AppTone.violet,
      ),
      _PipelineItem(
        'In stock',
        available,
        Icons.inventory_2_outlined,
        AppTone.violet,
      ),
      _PipelineItem('Sent', assigned, Icons.outgoing_mail, AppTone.amber),
      _PipelineItem(
        'Used',
        activated,
        Icons.check_circle_outline,
        AppTone.emerald,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: compact
                      ? (constraints.maxWidth - 10) / 2
                      : (constraints.maxWidth - 40) / 5,
                  child: _PipelineStep(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _PipelineItem {
  const _PipelineItem(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _PipelineStep extends StatelessWidget {
  const _PipelineStep({required this.item});
  final _PipelineItem item;

  @override
  Widget build(BuildContext context) {
    return _SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const SizedBox(height: 10),
          Text(
            '${item.value}',
            style: TextStyle(
              color: item.color,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          Text(
            item.label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTone.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class KeyInventoryPanel extends StatefulWidget {
  const KeyInventoryPanel({
    super.key,
    required this.keys,
    required this.dealers,
  });
  final List<Map<String, dynamic>> keys;
  final List<Map<String, dynamic>> dealers;

  @override
  State<KeyInventoryPanel> createState() => _KeyInventoryPanelState();
}

class _KeyInventoryPanelState extends State<KeyInventoryPanel> {
  String statusFilter = 'all';
  String dealerFilter = 'all';

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) return const Empty('No keys found.');
    final filtered = widget.keys.where((key) {
      final status = text(key['status']).toLowerCase();
      final dealerId = text(key['dealer_id']);
      final matchesStatus = statusFilter == 'all' || status == statusFilter;
      final matchesDealer = dealerFilter == 'all' || dealerId == dealerFilter;
      return matchesStatus && matchesDealer;
    }).toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final key in filtered) {
      final status = text(key['status'], fallback: 'available').toLowerCase();
      grouped.putIfAbsent(status, () => []).add(key);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusFilterChips(
              selected: statusFilter,
              options: const {
                'all': 'All',
                'available': 'In stock',
                'assigned': 'Sent',
                'activated': 'Used',
                'revoked': 'Cancelled',
              },
              onChanged: (value) => setState(() => statusFilter = value),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                initialValue: dealerFilter,
                decoration: const InputDecoration(
                  labelText: 'Dealer',
                  prefixIcon: Icon(Icons.storefront),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All dealers'),
                  ),
                  ...widget.dealers
                      .where((dealer) => dealerIdentifier(dealer).isNotEmpty)
                      .map(
                        (dealer) => DropdownMenuItem(
                          value: dealerIdentifier(dealer),
                          child: Text(text(dealer['name'], fallback: 'Dealer')),
                        ),
                      ),
                ],
                onChanged: (value) =>
                    setState(() => dealerFilter = value ?? 'all'),
              ),
            ),
            if (statusFilter != 'all' || dealerFilter != 'all')
              TextButton.icon(
                onPressed: () => setState(() {
                  statusFilter = 'all';
                  dealerFilter = 'all';
                }),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear filters'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const Empty('No keys match this filter.')
        else
          ...grouped.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      StatusPill(
                        label: resellerKeyStatusLabel(entry.key),
                        color: statusColor(entry.key),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entry.value.length} keys',
                        style: const TextStyle(
                          color: AppTone.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  KeyList(keys: entry.value),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class KeyRequestList extends StatelessWidget {
  const KeyRequestList({super.key, required this.requests});
  final List<Map<String, dynamic>> requests;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const Empty('No requests yet.');
    return Column(
      children: requests.map((request) {
        final status = text(request['status'], fallback: 'pending');
        final color = statusColor(status);
        final quantity = text(request['quantity'], fallback: '0');
        final dates = [
          if (text(request['created_at']).isNotEmpty)
            'Requested ${formatDateTime(request['created_at'])}',
          if (text(request['approved_at']).isNotEmpty)
            'Approved ${formatDateTime(request['approved_at'])}',
          if (text(request['rejected_at']).isNotEmpty)
            'Rejected ${formatDateTime(request['rejected_at'])}',
        ].join('  |  ');
        return _InfoTile(
          icon: iconForLabel(status),
          color: color,
          title: '$quantity keys',
          subtitle:
              '${text(request['justification'], fallback: 'No justification provided')}\n${dates.isEmpty ? 'Awaiting timeline update' : dates}',
          trailing: StatusPill(label: status, color: color),
        );
      }).toList(),
    );
  }
}

class KeyList extends StatelessWidget {
  const KeyList({super.key, required this.keys});
  final List<Map<String, dynamic>> keys;

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) return const Empty('No keys found.');
    return Column(
      children: keys.map((key) {
        final status = text(key['status'], fallback: 'available');
        return _InfoTile(
          icon: Icons.vpn_key,
          color: statusColor(status),
          title: text(
            key['key_string'] ?? key['key'] ?? key['id'],
            fallback: 'Activation key',
          ),
          subtitle: [
            if (text(key['dealer_name']).isNotEmpty)
              'Dealer: ${text(key['dealer_name'])}',
            if (text(key['created_at']).isNotEmpty)
              'Created: ${formatDateTime(key['created_at'])}',
            if (text(key['assigned_at']).isNotEmpty)
              'Sent to dealer: ${formatDateTime(key['assigned_at'])}',
            if (text(key['activated_at']).isNotEmpty)
              'Used by device: ${formatDateTime(key['activated_at'])}',
          ].join('\n'),
          trailing: StatusPill(
            label: resellerKeyStatusLabel(status),
            color: statusColor(status),
          ),
        );
      }).toList(),
    );
  }
}

class _InfoTile extends StatefulWidget {
  const _InfoTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<_InfoTile> createState() => _InfoTileState();
}

class _InfoTileState extends State<_InfoTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: _fast,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hovered ? AppTone.page : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hovered
                    ? widget.color.withValues(alpha: 0.22)
                    : AppTone.line,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon, color: widget.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: const TextStyle(
                          color: AppTone.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 10),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  bool get _isActive => label.toLowerCase() == 'active';

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isActive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: false))
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.5, 1.5),
                  duration: 900.ms,
                  curve: Curves.easeOut,
                )
                .fadeOut(begin: 1.0, duration: 900.ms),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    return pill;
  }
}

class _AnimatedSurface extends StatefulWidget {
  const _AnimatedSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<_AnimatedSurface> createState() => _AnimatedSurfaceState();
}

class _AnimatedSurfaceState extends State<_AnimatedSurface> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: _fast,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovered ? -1 : 0, 0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: AppTone.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hovered
                ? AppTone.emerald.withValues(alpha: 0.22)
                : AppTone.line,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hovered ? 0.07 : 0.035),
              blurRadius: hovered ? 18 : 10,
              offset: Offset(0, hovered ? 8 : 4),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTone.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTone.line),
      ),
      child: child,
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 126,
      child: _SoftPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppTone.ink,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTone.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final VoidCallback? onChanged;

  int get current => int.tryParse(controller.text.trim()) ?? min;
  int get effectiveMax => max < min ? min : max;

  void setQuantity(int value) {
    final next = value.clamp(min, effectiveMax).toInt();
    controller.text = '$next';
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final value = current;
    return Row(
      children: [
        IconButton(
          tooltip: 'Decrease',
          onPressed: value <= min ? null : () => setQuantity(value - 1),
          icon: const Icon(Icons.remove),
          style: IconButton.styleFrom(
            foregroundColor: AppTone.ink,
            backgroundColor: AppTone.page,
            side: const BorderSide(color: AppTone.line),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => onChanged?.call(),
            decoration: InputDecoration(
              labelText: label,
              helperText: 'Allowed range: $min-$effectiveMax',
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: 'Increase',
          onPressed: value >= effectiveMax
              ? null
              : () => setQuantity(value + 1),
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            foregroundColor: AppTone.ink,
            backgroundColor: AppTone.page,
            side: const BorderSide(color: AppTone.line),
          ),
        ),
      ],
    );
  }
}

class _SecureInput extends StatefulWidget {
  const _SecureInput({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  State<_SecureInput> createState() => _SecureInputState();
}

class _SecureInputState extends State<_SecureInput> {
  final focus = FocusNode();
  bool focused = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(() => setState(() => focused = focus.hasFocus));
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _fast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppTone.emerald.withValues(alpha: 0.1),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: focus,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        style: widget.obscure
            ? GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.0,
                color: AppTone.ink,
              )
            : GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                color: AppTone.ink,
              ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: focused ? AppTone.emerald : AppTone.muted,
          ),
          prefixIcon: Icon(
            widget.icon,
            color: focused ? AppTone.emerald : AppTone.muted,
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    required this.tone,
    required this.icon,
  });
  final String message;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tone, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Page(
      title: title,
      subtitle: 'Loading latest operational data',
      children: [
        Shimmer.fromColors(
          baseColor: const Color(0xFFE5E7EB),
          highlightColor: Colors.white,
          child: _AnimatedSurface(
            child: Column(
              children: List.generate(
                4,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 3 ? 0 : 12),
                  child: _SkeletonLine(widthFactor: 0.95 - (index * 0.12)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Public notice widget for use in external screen files.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    required this.tone,
    required this.icon,
  });
  final String message;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tone, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Public skeleton placeholder for use in external screen files.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: AppTone.line,
        borderRadius: BorderRadius.circular(8),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fade(begin: 0.45, end: 1, duration: 720.ms);
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child:
          Container(
                height: 16,
                decoration: BoxDecoration(
                  color: AppTone.line,
                  borderRadius: BorderRadius.circular(14),
                ),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .fade(begin: 0.45, end: 1, duration: 720.ms),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTone.page,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTone.line),
            ),
            child: const Icon(Icons.inbox_outlined, color: AppTone.muted),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTone.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class Fields extends StatelessWidget {
  const Fields({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 700;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map(
              (child) => SizedBox(
                width: wide ? (c.maxWidth - 12) / 2 : c.maxWidth,
                child: child,
              ),
            )
            .toList(),
      );
    },
  );
}

class Input extends StatelessWidget {
  const Input(this.controller, this.label, {super.key, this.obscure = false});
  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        obscure ? Icons.lock_outline : Icons.edit_outlined,
        color: AppTone.muted,
      ),
    ),
  );
}

class Bars extends StatelessWidget {
  const Bars({super.key, required this.values});
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    final parsed = values.map(
      (k, v) => MapEntry(k, num.tryParse(v.toString()) ?? 0),
    );
    final max = parsed.values.fold<num>(1, (a, b) => b > a ? b : a);
    final entries = parsed.entries.toList();
    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          maxY: max.toDouble() + 1,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTone.subtle.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 34),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= entries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entries[i].key,
                      style: const TextStyle(
                        color: AppTone.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: entries.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: item.value.toDouble(),
                  width: 24,
                  borderRadius: BorderRadius.circular(14),
                  color: statusColor(item.key),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return {};
}

List<Map<String, dynamic>> asList(dynamic value, String key) {
  final data = asMap(value);
  final list = data[key];
  if (list is List) return list.map(asMap).toList();
  if (value is List) return value.map(asMap).toList();
  return [];
}

String text(dynamic value, {String fallback = ''}) {
  final result = value?.toString() ?? '';
  return result.isEmpty ? fallback : result;
}

int countByStatus(List<Map<String, dynamic>> items, String status) {
  final expected = status.toLowerCase();
  return items
      .where((item) => text(item['status']).toLowerCase() == expected)
      .length;
}

String dealerIdentifier(Map<String, dynamic> dealer) {
  return text(
    dealer['id'] ?? dealer['dealer_id'] ?? dealer['user_id'] ?? dealer['uuid'],
  );
}

String keyGroupLabel(String status) {
  return dealerKeyStatusLabel(status);
}

String dealerKeyStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'assigned':
      return 'Ready for activation';
    case 'activated':
      return 'Used by device';
    case 'revoked':
      return 'Cancelled';
    case 'available':
      return 'Ready stock';
    default:
      return text(status, fallback: 'Other');
  }
}

String resellerKeyStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'available':
      return 'In reseller stock';
    case 'assigned':
      return 'Sent to dealer';
    case 'activated':
      return 'Used by device';
    case 'revoked':
      return 'Cancelled';
    default:
      return text(status, fallback: 'Other');
  }
}

String alertStatusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'active':
    case 'open':
    case 'unread':
      return 'Open';
    case 'read':
      return 'Read';
    case 'resolved':
      return 'Resolved';
    default:
      return text(status, fallback: 'Open');
  }
}

String alertTypeTitle(String type) {
  final normalized = type.toLowerCase();
  if (normalized.contains('geo')) return 'Device left geofence';
  if (normalized.contains('lock')) return 'Locked device needs follow-up';
  if (normalized.contains('stock') || normalized.contains('key')) {
    return 'Activation key stock warning';
  }
  if (normalized.contains('delivery') || normalized.contains('notification')) {
    return 'Notification delivery warning';
  }
  if (normalized.contains('request')) return 'Pending reseller key request';
  return text(type, fallback: 'Alert');
}

String formatDateTime(dynamic value) {
  final raw = text(value);
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('MMM d, yyyy h:mm a').format(parsed.toLocal());
}

String? emptyToNull(String value) => value.trim().isEmpty ? null : value.trim();

String readableError(Object? error) {
  if (error is DioException) {
    final data = asMap(error.response?.data);
    final code = text(data['code']).toUpperCase();
    if (code == 'TOKEN_EXPIRED' ||
        code == 'INVALID_SESSION' ||
        code == 'TOKEN_REVOKED') {
      return 'Your session expired. Please sign in again.';
    }
    final serverMessage = text(data['message'] ?? data['error']);
    if (serverMessage.isNotEmpty) return serverMessage;

    final baseUrl = text(
      error.requestOptions.baseUrl,
      fallback: 'the API server',
    );
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Could not connect to $baseUrl before the request timed out. Check that the API is running and reachable from Chrome.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The API request to $baseUrl took too long. Please try again after the server finishes waking up.';
      case DioExceptionType.connectionError:
        return 'Could not reach $baseUrl from this browser. Check the API URL and CORS settings.';
      case DioExceptionType.badCertificate:
        return 'The API certificate could not be trusted by this browser.';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        return text(error.message, fallback: 'Network error');
    }
  }
  return text(error).replaceFirst('Exception: ', '');
}

Color statusColor(String status) {
  final s = status.toLowerCase();
  if (s.contains('active') ||
      s.contains('available') ||
      s.contains('approved')) {
    return AppTone.emerald;
  }
  if (s.contains('lock') || s.contains('reject') || s.contains('revoked')) {
    return AppTone.red;
  }
  if (s.contains('pending') || s.contains('assigned')) return AppTone.amber;
  return AppTone.blue;
}

IconData iconForLabel(String label) {
  final value = label.toLowerCase();
  if (value.contains('dealer')) return Icons.storefront;
  if (value.contains('device') || value.contains('enrolled')) {
    return Icons.phone_android;
  }
  if (value.contains('key')) return Icons.vpn_key;
  if (value.contains('locked')) return Icons.lock_outline;
  if (value.contains('pending')) return Icons.pending_actions;
  if (value.contains('activated') || value.contains('available')) {
    return Icons.check_circle_outline;
  }
  if (value.contains('decoupled')) return Icons.link_off;
  return Icons.insights;
}

Future<bool> confirmLogout(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign out of EMI Locker?'),
      content: const Text(
        'You will be logged out of this dealer workspace and will need to sign in again to continue.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTone.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  return result ?? false;
}

void snack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

// ── Fraud center entry widget for DealerTools ─────────────────────────────────

class _FraudCenterEntry extends StatefulWidget {
  const _FraudCenterEntry({required this.api});
  final ApiClient api;

  @override
  State<_FraudCenterEntry> createState() => _FraudCenterEntryState();
}

class _FraudCenterEntryState extends State<_FraudCenterEntry> {
  int _openCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final res = await widget.api.get('/api/v1/alerts');
      final data = asMap(res.data);
      final list = (data['alerts'] as List? ?? []).map(asMap).toList();
      final open = list
          .where((a) => text(a['status']) != 'resolved')
          .length;
      if (mounted) setState(() => _openCount = open);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (_openCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTone.danger,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_openCount open',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Open Fraud Center'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FraudCenterScreen(api: widget.api),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Google Drive status tile for SettingsPage ─────────────────────────────────

class _GoogleDriveStatusTile extends StatefulWidget {
  const _GoogleDriveStatusTile();

  @override
  State<_GoogleDriveStatusTile> createState() => _GoogleDriveStatusTileState();
}

class _GoogleDriveStatusTileState extends State<_GoogleDriveStatusTile> {
  bool _loading = true;
  bool _isBound = false;
  String _email = '';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final bound = await GoogleVault.isBound();
    final email = await GoogleVault.boundEmail() ?? '';
    if (mounted) setState(() { _isBound = bound; _email = email; _loading = false; });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final snapshot = await LocalVault.read();
      if (snapshot != null && !snapshot.isEmpty) {
        await GoogleVault.syncVaultBackup(snapshot.toJson());
        if (mounted) snack(context, 'Vault synced to Google Drive');
      } else {
        if (mounted) snack(context, 'Nothing to sync yet');
      }
    } catch (e) {
      if (mounted) snack(context, 'Sync failed: ${readableError(e)}');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonBox(width: double.infinity, height: 44);

    return Row(
      children: [
        Icon(
          _isBound ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
          color: _isBound ? AppTone.brand : AppTone.muted,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _isBound ? _email : 'Not connected',
            style: TextStyle(color: _isBound ? AppTone.ink : AppTone.muted, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_isBound)
          IconButton(
            icon: _syncing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded, size: 18),
            tooltip: 'Sync now',
            onPressed: _syncing ? null : _syncNow,
            color: AppTone.brand,
          ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GoogleDriveOnboardingScreen()),
          ).then((_) => _check()),
          child: const Text('Configure'),
        ),
      ],
    );
  }
}
