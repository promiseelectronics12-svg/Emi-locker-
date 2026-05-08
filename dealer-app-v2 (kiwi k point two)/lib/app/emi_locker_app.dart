import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/local_vault.dart';

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
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

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
  if (kDebugMode) return localApiBaseUrl;
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

Color roleAccent(AppUser user) =>
    user.isReseller ? AppTone.accent : AppTone.brand;
Color roleAccentDark(AppUser user) =>
    user.isReseller ? const Color(0xFF4F46E5) : AppTone.brandDark;
Color roleAccentLight(AppUser user) =>
    user.isReseller ? AppTone.accentLight : AppTone.brandLight;

Future<void> bootstrapEmiLockerApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
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

  @override
  void initState() {
    super.initState();
    api.onSessionExpired = _sessionExpired;
    _restore();
  }

  Future<void> _restore() async {
    final access = await storage.read(key: 'accessToken');
    final refresh = await storage.read(key: 'refreshToken');
    final rawUser = await storage.read(key: 'user');
    if (access != null && refresh != null && rawUser != null) {
      final user = AppUser.fromJson(asMap(jsonDecode(rawUser)));
      api.setTokens(accessToken: access, refreshToken: refresh);
      session = Session(user: user, accessToken: access, refreshToken: refresh);
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
  }

  Future<void> _logout() async {
    try {
      await api.post('/api/v1/auth/logout');
    } catch (_) {}
    api.clearTokens();
    await storage.deleteAll();
    setState(() => session = null);
  }

  Future<void> _sessionExpired() async {
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
          : session == null
          ? LoginScreen(api: api, onAuthenticated: _authenticated)
          : Workspace(api: api, session: session!, onLogout: _logout),
    );
  }
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
  final code = TextEditingController(text: '000000');
  bool busy = false;
  String? error;

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final loginResponse = await widget.api.post(
        '/api/v1/auth/login',
        data: {'email': email.text.trim(), 'password': password.text},
      );
      final tempToken = asMap(loginResponse.data)['tempToken']?.toString();
      if (tempToken == null) throw Exception('Temporary token missing');
      final verifyResponse = await widget.api.post(
        '/api/v1/auth/2fa/verify',
        data: {'tempToken': tempToken, 'code': code.text.trim()},
      );
      final data = asMap(verifyResponse.data);
      final access = data['accessToken']?.toString();
      final refresh = data['refreshToken']?.toString();
      if (access == null || refresh == null) throw Exception('Tokens missing');
      widget.onAuthenticated(
        Session(
          user: AppUser.fromJson(asMap(data['user'])),
          accessToken: access,
          refreshToken: refresh,
        ),
      );
    } catch (e) {
      setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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

  Widget _buildLoginCard(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 450),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand accent stripe
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTone.accent, AppTone.brand],
                ),
              ),
            ),
            _AnimatedSurface(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header: logo + text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const _BrandMark(size: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'EMI Locker',
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: AppTone.ink,
                                    letterSpacing: -0.8,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Secure workspace access',
                                  style: GoogleFonts.inter(
                                    color: AppTone.muted,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _SecureInput(
                        controller: email,
                        label: 'Email address',
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _SecureInput(
                        controller: password,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true,
                      ),
                      const SizedBox(height: 18),
                      _SixDigitCodeInput(controller: code),
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
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: busy ? null : login,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(busy ? 'Signing in…' : 'Sign in securely'),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTone.page,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTone.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Demo accounts',
                              style: TextStyle(
                                color: AppTone.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _DemoAccountButton(
                                  label: 'Dealer demo',
                                  onPressed: () {
                                    email.text = 'dealer@emi-locker.com';
                                    password.text = 'Demo@123456';
                                  },
                                ),
                                _DemoAccountButton(
                                  label: 'Reseller demo',
                                  onPressed: () {
                                    email.text = 'reseller@emi-locker.com';
                                    password.text = 'Demo@123456';
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: 360.ms, delay: 80.ms)
                .slideY(begin: 0.04, end: 0),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 820;

    if (compact) {
      return Scaffold(
        backgroundColor: AppTone.ink,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MobileLoginBriefing()
                .animate()
                .fadeIn(duration: 420.ms)
                .slideY(begin: -0.02, end: 0),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTone.page,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
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
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTone.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: const _LoginBriefing()
                        .animate()
                        .fadeIn(duration: 420.ms)
                        .slideX(begin: -0.03, end: 0),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
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
    );
  }
}

class _MobileLoginBriefing extends StatelessWidget {
  const _MobileLoginBriefing();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1117), Color(0xFF151B2E)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _BrandMark(size: 38, dark: true),
                      const SizedBox(width: 12),
                      const Text(
                        'EMI Locker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Command center for\nfinanced device control',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      height: 1.15,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _LoginSignal(
                        icon: Icons.key_outlined,
                        label: 'Activation keys',
                      ),
                      _LoginSignal(
                        icon: Icons.phone_android,
                        label: 'Device lock flow',
                      ),
                      _LoginSignal(
                        icon: Icons.shield_outlined,
                        label: 'Enterprise grade',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBriefing extends StatelessWidget {
  const _LoginBriefing();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 300),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1117), Color(0xFF151B2E)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
            // Bottom fade overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF0D1117).withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(size: 48, dark: true),
                  const SizedBox(height: 48),
                  Text(
                    'Command center\nfor financed\ndevice control',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 38,
                      height: 1.05,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Dealer and reseller operations\nin one controlled workspace.',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: const [
                      _LoginSignal(
                        icon: Icons.key_outlined,
                        label: 'Activation keys',
                      ),
                      _LoginSignal(
                        icon: Icons.phone_android,
                        label: 'Device lock flow',
                      ),
                      _LoginSignal(
                        icon: Icons.route_outlined,
                        label: 'Field location',
                      ),
                      _LoginSignal(
                        icon: Icons.shield_outlined,
                        label: 'Enterprise grade',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginSignal extends StatelessWidget {
  const _LoginSignal({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF34D399), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
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

class _DemoAccountButton extends StatelessWidget {
  const _DemoAccountButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.person_outline, size: 18),
      label: Text(label),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;
    const spacing = 32.0;
    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class ActivationCodePayload {
  const ActivationCodePayload({
    required this.activationCode,
    required this.verifyEndpoint,
  });
  final String activationCode;
  final String verifyEndpoint;

  String toQrJson() => jsonEncode({
    'type': 'emi_locker_activation_code',
    'activationCode': activationCode,
    'verifyEndpoint': verifyEndpoint,
  });
}

class _FloatingWorkspaceControls extends StatelessWidget {
  const _FloatingWorkspaceControls({
    required this.user,
    required this.api,
    required this.onSettings,
  });
  final AppUser user;
  final ApiClient api;
  final VoidCallback onSettings;

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
                _AlertBell(api: api, accent: accent),
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
  const _AlertBell({required this.api, required this.accent});
  final ApiClient api;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Alert Center',
      child: IconButton.filledTonal(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _AlertCenterSheet(api: api, accent: accent),
        ),
        icon: const Icon(Icons.notifications_active_outlined),
        style: IconButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}

class _AlertCenterSheet extends StatelessWidget {
  const _AlertCenterSheet({required this.api, required this.accent});
  final ApiClient api;
  final Color accent;

  Future<List<Map<String, dynamic>>> loadAlerts() async {
    final response = await api.get('/api/v1/alerts');
    return asList(response.data, 'alerts');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Alert Center',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadAlerts(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return Shimmer.fromColors(
                        baseColor: const Color(0xFFE5E7EB),
                        highlightColor: Colors.white,
                        child: Column(
                          children: List.generate(
                            4,
                            (index) => const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: _SoftPanel(
                                child: _SkeletonLine(widthFactor: 0.82),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _InlineNotice(
                        message:
                            'Alert Center is not available yet. ${readableError(snapshot.error)}',
                        tone: AppTone.amber,
                        icon: Icons.cloud_off_outlined,
                      );
                    }
                    final alerts = snapshot.data ?? [];
                    if (alerts.isEmpty) {
                      return const Empty('No active alerts right now.');
                    }
                    return ListView(
                      children: alerts
                          .map((alert) => _AlertTile(alert: alert))
                          .toList(),
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
          child: AnimatedContainer(
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

class DealerDashboard extends StatelessWidget {
  const DealerDashboard({
    super.key,
    required this.api,
    required this.onNavigate,
  });
  final ApiClient api;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Dealer dashboard',
      loader: () async {
        final stats = asMap((await api.get('/api/v1/dealer/stats')).data);
        final keys = asMap((await api.get('/api/v1/keys/my-keys')).data);
        final devices = asMap((await api.get('/api/v1/dealer/devices')).data);
        return {
          'stats': stats,
          'keys': asList(keys, 'keys'),
          'devices': asList(devices, 'devices'),
        };
      },
      builder: (context, data, reload) {
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
              child: _DealerQuickActions(onNavigate: onNavigate),
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
  const _DealerQuickActions({required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        'Enroll device',
        Icons.qr_code_2_outlined,
        () => onNavigate(2),
      ),
      _QuickAction('View keys', Icons.vpn_key_outlined, () => onNavigate(3)),
      _QuickAction(
        'Pull location',
        Icons.location_searching,
        () => onNavigate(1),
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
      return const _InlineNotice(
        message:
            'Workspace is clear. Keys and devices are in a healthy operating state.',
        tone: AppTone.emerald,
        icon: Icons.check_circle_outline,
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

class DealerDevices extends StatelessWidget {
  const DealerDevices({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Devices',
      loader: () async => asMap((await api.get('/api/v1/dealer/devices')).data),
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
                                : () => showDialog<void>(
                                    context: context,
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
      await widget.api.post(
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
  String? selectedKey;
  ActivationCodePayload? activationPayload;
  String? message;
  late Future<Map<String, dynamic>> future = loadData();

  Future<Map<String, dynamic>> loadData() async {
    final assigned = asMap(
      (await widget.api.get(
        '/api/v1/keys/my-keys',
        query: {'status': 'assigned'},
      )).data,
    );
    final stats = asMap((await widget.api.get('/api/v1/dealer/stats')).data);
    final devices = asMap(
      (await widget.api.get('/api/v1/dealer/devices')).data,
    );
    return {
      'assignedKeys': asList(assigned, 'keys')
          .where((key) => text(key['status']).toLowerCase() == 'assigned')
          .toList(),
      'stats': stats,
      'devices': asList(devices, 'devices'),
    };
  }

  Future<void> refreshData() async {
    final next = loadData();
    setState(() {
      future = next;
    });
    await next;
  }

  Map<String, dynamic>? selectedKeyRow(
    List<Map<String, dynamic>> assignedKeys,
  ) {
    for (final key in assignedKeys) {
      if (text(key['key_string'] ?? key['key']) == selectedKey) return key;
    }
    return null;
  }

  String? validate(List<Map<String, dynamic>> assignedKeys) {
    if (assignedKeys.isEmpty) {
      return 'No ready activation codes available. Ask your reseller to send stock.';
    }
    if (selectedKey == null || selectedKeyRow(assignedKeys) == null) {
      return 'Choose a ready activation code.';
    }
    return null;
  }

  void createActivationPayload(List<Map<String, dynamic>> assignedKeys) {
    final validation = validate(assignedKeys);
    if (validation != null) {
      setState(() => message = validation);
      return;
    }
    setState(() {
      activationPayload = ActivationCodePayload(
        activationCode: selectedKey!,
        verifyEndpoint:
            '${configuredApiBaseUrl()}/api/v1/device-activation/verify',
      );
      message =
          'Activation code is ready. The key is not consumed until the phone verifies itself.';
    });
  }

  void enrollAnother() {
    selectedKey = null;
    activationPayload = null;
    message = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? {};
        final assignedKeys =
            (data['assignedKeys'] as List<Map<String, dynamic>>?) ?? [];
        final stats = asMap(data['stats']);
        final devices = (data['devices'] as List<Map<String, dynamic>>?) ?? [];
        final selected = selectedKeyRow(assignedKeys);
        final hasUsableKeys = assignedKeys.isNotEmpty;
        if (selectedKey != null && selected == null) selectedKey = null;
        return Page(
          title: 'Enroll device',
          subtitle: 'Show a ready activation code to the customer phone',
          reload: refreshData,
          children: [
            StatGrid(
              cards: [
                StatCard(
                  'Ready codes',
                  assignedKeys.length,
                  color: AppTone.brand,
                  icon: Icons.vpn_key_outlined,
                ),
                StatCard(
                  'Used by devices',
                  stats['activated_keys'],
                  color: AppTone.emerald,
                  icon: Icons.check_circle_outline,
                ),
                StatCard(
                  'Enrolled devices',
                  devices.length,
                  color: AppTone.blue,
                  icon: Icons.phone_android_outlined,
                ),
              ],
            ),
            Section(
              title: 'Activation steps',
              child: _EnrollmentWorkflowStrip(
                currentStep: activationPayload != null
                    ? 3
                    : selected != null
                    ? 2
                    : 1,
              ),
            ),
            Section(
              title: '1. Choose ready activation code',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasUsableKeys)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _InlineNotice(
                        message:
                            'No ready activation codes available. Ask your reseller to send stock.',
                        tone: AppTone.amber,
                        icon: Icons.key_off_outlined,
                      ),
                    ),
                  if (hasUsableKeys)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: assignedKeys.map((key) {
                        final code = text(key['key_string'] ?? key['key']);
                        final active = code == selectedKey;
                        return SizedBox(
                          width: 260,
                          child: _ActivationCodeCard(
                            code: code,
                            status: text(key['status'], fallback: 'assigned'),
                            selected: active,
                            onTap: () => setState(() {
                              selectedKey = code;
                              activationPayload = null;
                              message = null;
                            }),
                          ),
                        );
                      }).toList(),
                    ),
                  if (selected != null) ...[
                    const SizedBox(height: 12),
                    _SelectedKeyPreview(keyRow: selected),
                  ],
                ],
              ),
            ),
            Section(
              title: '2. Show this code to the customer phone',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _InlineNotice(
                    message:
                        'The phone enters or scans this code. The backend consumes it only after real device verification.',
                    tone: AppTone.info,
                    icon: Icons.verified_user_outlined,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: !hasUsableKeys
                        ? null
                        : () => createActivationPayload(assignedKeys),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Show activation code and QR'),
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _InlineNotice(
                        message: message!,
                        tone: activationPayload == null
                            ? AppTone.red
                            : AppTone.emerald,
                        icon: activationPayload == null
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                      ),
                    ),
                ],
              ),
            ),
            if (activationPayload != null)
              Section(
                title: '3. Phone verifies and device appears',
                child: _EnrollmentSuccess(
                  payload: activationPayload!,
                  onEnrollAnother: enrollAnother,
                  onViewDevices: () => widget.onNavigate(1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EnrollmentWorkflowStrip extends StatelessWidget {
  const _EnrollmentWorkflowStrip({required this.currentStep});
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _PipelineItem('Choose ready code', 1, Icons.key_rounded, AppTone.brand),
      _PipelineItem('Show to phone', 2, Icons.qr_code_2_outlined, AppTone.blue),
      _PipelineItem('Phone verifies', 3, Icons.verified_user, AppTone.emerald),
      _PipelineItem('Device appears', 4, Icons.phone_android, AppTone.violet),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: steps
          .map(
            (step) => SizedBox(
              width: 170,
              child: _SoftPanel(
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: step.value <= currentStep
                            ? step.color.withValues(alpha: 0.13)
                            : AppTone.page,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: step.value <= currentStep
                              ? step.color.withValues(alpha: 0.28)
                              : AppTone.line,
                        ),
                      ),
                      child: Icon(
                        step.value < currentStep ? Icons.check : step.icon,
                        color: step.value <= currentStep
                            ? step.color
                            : AppTone.muted,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: step.value <= currentStep
                              ? AppTone.ink
                              : AppTone.muted,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ActivationCodeCard extends StatelessWidget {
  const _ActivationCodeCard({
    required this.code,
    required this.status,
    required this.selected,
    required this.onTap,
  });
  final String code;
  final String status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = status.toLowerCase() == 'assigned'
        ? AppTone.brand
        : statusColor(status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: _fast,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTone.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTone.brand : AppTone.subtle,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.035),
              blurRadius: selected ? 18 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.key_rounded,
              color: selected ? AppTone.brand : color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                code,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontWeight: FontWeight.w900,
                  color: AppTone.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(label: dealerKeyStatusLabel(status), color: color),
          ],
        ),
      ),
    );
  }
}

class _SelectedKeyPreview extends StatelessWidget {
  const _SelectedKeyPreview({required this.keyRow});
  final Map<String, dynamic> keyRow;

  @override
  Widget build(BuildContext context) {
    final status = text(keyRow['status'], fallback: 'assigned');
    final color = status.toLowerCase() == 'assigned'
        ? AppTone.brand
        : statusColor(status);
    return _SoftPanel(
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              [
                'Ready activation code: ${text(keyRow['key_string'] ?? keyRow['key'])}',
                if (text(keyRow['assigned_at']).isNotEmpty)
                  'Received in stock ${formatDateTime(keyRow['assigned_at'])}',
                'The phone will consume this code only after device verification.',
              ].join('\n'),
              style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700),
            ),
          ),
          StatusPill(label: dealerKeyStatusLabel(status), color: color),
        ],
      ),
    );
  }
}

class _EnrollmentSuccess extends StatelessWidget {
  const _EnrollmentSuccess({
    required this.payload,
    required this.onEnrollAnother,
    required this.onViewDevices,
  });
  final ActivationCodePayload payload;
  final VoidCallback onEnrollAnother;
  final VoidCallback onViewDevices;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoftPanel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailFact('Activation code', payload.activationCode),
              const _DetailFact('Code status', 'Ready until phone verifies'),
              const _DetailFact('Next step', 'Enter or scan on phone'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(child: QrImageView(data: payload.toQrJson(), size: 260)),
        const SizedBox(height: 12),
        SelectableText(
          payload.activationCode,
          textAlign: TextAlign.center,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: AppTone.brandDark,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: onEnrollAnother,
              icon: const Icon(Icons.add),
              label: const Text('Enroll another device'),
            ),
            OutlinedButton.icon(
              onPressed: onViewDevices,
              icon: const Icon(Icons.phone_android_outlined),
              label: const Text('View devices'),
            ),
          ],
        ),
      ],
    );
  }
}

class DealerKeys extends StatelessWidget {
  const DealerKeys({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Dealer keys',
      loader: () async => asMap((await api.get('/api/v1/keys/my-keys')).data),
      builder: (context, data, reload) {
        final keys = asList(data, 'keys');
        return Page(
          title: 'Dealer keys',
          subtitle:
              '${countByStatus(keys, 'assigned')} ready for activation, ${countByStatus(keys, 'activated')} used by devices',
          reload: reload,
          children: [
            StatGrid(
              cards: [
                StatCard(
                  'Ready for activation',
                  countByStatus(keys, 'assigned'),
                  color: AppTone.brand,
                  icon: Icons.vpn_key_outlined,
                ),
                StatCard(
                  'Used by devices',
                  countByStatus(keys, 'activated'),
                  color: AppTone.emerald,
                  icon: Icons.check_circle_outline,
                ),
                StatCard(
                  'Cancelled',
                  countByStatus(keys, 'revoked'),
                  color: AppTone.red,
                  icon: Icons.block,
                ),
              ],
            ),
            Section(
              title: 'Activation code inventory',
              child: DealerKeyInventory(keys: keys),
            ),
          ],
        );
      },
    );
  }
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
  bool _qrBusy = false;
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
            style: FilledButton.styleFrom(backgroundColor: AppTone.error),
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

  Future<void> _showQr() async {
    final id = _selectedDeviceId;
    if (id == null) return;
    setState(() => _qrBusy = true);
    try {
      final res = await widget.api.post(
        '/api/v1/lock/paut',
        data: {'deviceId': id},
      );
      final token = text(asMap(res.data)['token']);
      if (token.isEmpty) throw Exception('No token returned');
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Scan on customer locked screen'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: token, size: 240),
                const SizedBox(height: 12),
                const _InlineNotice(
                  message: 'Valid 48 hours. Tied to this device only. Keep this QR private.',
                  tone: AppTone.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    } finally {
      if (mounted) setState(() => _qrBusy = false);
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
          decoration: const InputDecoration(
            labelText: 'Select device',
            prefixIcon: Icon(Icons.phone_android_outlined),
          ),
          items: devices.map((d) {
            final label =
                '${text(d['device_name'] ?? d['model'], fallback: 'Device')} — ${text(d['imei'], fallback: '')}';
            return DropdownMenuItem(
              value: text(d['id']),
              child: Text(label, overflow: TextOverflow.ellipsis),
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
              color: AppTone.success.withOpacity(0.08),
              border: Border.all(color: AppTone.success.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_open_outlined, color: AppTone.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Grace period active',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.success),
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
                  style: TextButton.styleFrom(foregroundColor: AppTone.error),
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
            OutlinedButton.icon(
              onPressed: _selectedDeviceId == null || _qrBusy ? null : _showQr,
              icon: _qrBusy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2_outlined),
              label: Text(_qrBusy ? 'Generating…' : 'Show dealer QR'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'SMS: customer calls you, you pick the grace time and send the code. '
          'No internet needed on customer\'s device — they enter the 6-digit code on the locked screen.\n'
          'QR: you must be physically present. Customer scans it on the locked screen.',
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

class ResellerDashboard extends StatelessWidget {
  const ResellerDashboard({super.key, required this.api});
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return DataPage<Map<String, dynamic>>(
      title: 'Reseller dashboard',
      loader: () async => asMap((await api.get('/api/v1/reseller/stats')).data),
      builder: (context, stats, reload) => Page(
        title: 'Reseller dashboard',
        subtitle: 'Dealer network and key inventory',
        reload: reload,
        children: [
          StatGrid(
            cards: [
              StatCard('Dealers', stats['total_dealers'], icon: Icons.groups),
              StatCard(
                'In reseller stock',
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
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CreateDealerDialog(api: api),
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
      title: 'Key inventory',
      loader: () async {
        final inventory = asMap(
          (await api.get('/api/v1/reseller/keys/inventory')).data,
        );
        final requests = asMap(
          (await api.get('/api/v1/reseller/keys/requests')).data,
        );
        final quota = asMap((await api.get('/api/v1/reseller/quota')).data);
        final dealers = asMap((await api.get('/api/v1/reseller/dealers')).data);
        return {
          'keys': asList(inventory, 'keys'),
          'requests': asList(requests, 'requests'),
          'quota': quota,
          'dealers': asList(dealers, 'dealers'),
        };
      },
      builder: (context, data, reload) {
        final keys = (data['keys'] as List<Map<String, dynamic>>?) ?? [];
        final requests =
            (data['requests'] as List<Map<String, dynamic>>?) ?? [];
        final quota = asMap(data['quota']);
        final dealers = (data['dealers'] as List<Map<String, dynamic>>?) ?? [];
        final availableCount = countByStatus(keys, 'available');
        final assignedCount = countByStatus(keys, 'assigned');
        final activatedCount = countByStatus(keys, 'activated');
        final pendingRequests = requests
            .where(
              (request) => text(request['status']).toLowerCase() == 'pending',
            )
            .length;
        return Page(
          title: 'Key inventory',
          subtitle:
              'Quota ${quota['used_keys'] ?? 0}/${quota['monthly_quota'] ?? 100}',
          reload: reload,
          actions: [
            FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RequestKeysDialog(
                  api: api,
                  quota: quota,
                  onSubmitted: reload,
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Request keys'),
            ),
            OutlinedButton.icon(
              onPressed: dealers.isEmpty
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
                          availableCount: availableCount,
                          onAssigned: reload,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send to dealer'),
            ),
          ],
          children: [
            Section(
              title: 'Dealer key handoff',
              child: _ResellerKeyHandoffPanel(
                dealers: dealers,
                availableCount: availableCount,
                assignedCount: assignedCount,
                onRequestKeys: () => showDialog<void>(
                  context: context,
                  builder: (_) => RequestKeysDialog(
                    api: api,
                    quota: quota,
                    onSubmitted: reload,
                  ),
                ),
                onSendKeys: dealers.isEmpty
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
                            availableCount: availableCount,
                            onAssigned: reload,
                          ),
                        ),
                      ),
              ),
            ),
            StatGrid(
              cards: [
                StatCard(
                  'In stock',
                  availableCount,
                  color: AppTone.violet,
                  icon: Icons.inventory_2_outlined,
                ),
                StatCard(
                  'Sent to dealers',
                  assignedCount,
                  color: AppTone.amber,
                  icon: Icons.outgoing_mail,
                ),
                StatCard(
                  'Used by devices',
                  activatedCount,
                  color: AppTone.emerald,
                  icon: Icons.check_circle_outline,
                ),
                StatCard(
                  'Pending requests',
                  pendingRequests,
                  color: AppTone.red,
                  icon: Icons.pending_actions,
                ),
              ],
            ),
            Section(
              title: 'Inventory pipeline',
              child: InventoryPipeline(
                requested: pendingRequests,
                approved: requests
                    .where(
                      (request) =>
                          text(request['status']).toLowerCase() == 'approved',
                    )
                    .length,
                available: availableCount,
                assigned: assignedCount,
                activated: activatedCount,
              ),
            ),
            Section(
              title: 'Reseller stock movement',
              child: KeyInventoryPanel(keys: keys, dealers: dealers),
            ),
            Section(
              title: 'Requests',
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
      await widget.api.post(
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

  Future<void> pull() async {
    try {
      final response = await widget.api.post(
        '/api/v1/location/${widget.deviceId}/pull',
      );
      setState(() => message = jsonEncode(asMap(response.data)));
    } catch (e) {
      setState(() => message = readableError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pull location'),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      FilledButton(onPressed: pull, child: const Text('Pull')),
    ],
  );
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
    subtitle: 'Approved keys land in reseller inventory.',
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
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_outlined),
        label: Text(busy ? 'Submitting' : 'Submit request'),
      ),
    ],
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
        const SizedBox(height: 16),
        QuantityStepper(
          controller: quantity,
          label: 'Request quantity',
          min: 1,
          max: maxPerRequest,
          onChanged: () => setState(() => error = null),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: justification,
          maxLines: 3,
          onChanged: (_) => setState(() => error = null),
          decoration: const InputDecoration(
            labelText: 'Justification',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
        const SizedBox(height: 14),
        _RequestPreview(
          quantity: requestedQuantity <= 0 ? 0 : requestedQuantity,
          remainingAfter: (remainingQuota - requestedQuantity).clamp(
            0,
            remainingQuota,
          ),
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
  final quantity = TextEditingController(text: '1');
  String? error;
  bool busy = false;

  int get requestedQuantity => int.tryParse(quantity.text.trim()) ?? 0;

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  String? validate(int available) {
    if (requestedQuantity <= 0) return 'Enter a valid quantity.';
    if (requestedQuantity > available) {
      return 'Only $available keys are available for assignment.';
    }
    return null;
  }

  Future<int> loadAvailableCount() async {
    if (widget.availableCount != null) return widget.availableCount!;
    final inventory = asMap(
      (await widget.api.get('/api/v1/reseller/keys/inventory')).data,
    );
    return countByStatus(asList(inventory, 'keys'), 'available');
  }

  Future<void> submit(int available) async {
    final validation = validate(available);
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
        '/api/v1/reseller/dealers/${widget.dealerId}/assign-keys',
        data: {'quantity': requestedQuantity},
      );
      await widget.onAssigned?.call();
      if (mounted) {
        Navigator.pop(context);
        snack(context, '$requestedQuantity keys assigned');
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: loadAvailableCount(),
      builder: (context, snapshot) {
        final available = snapshot.data ?? widget.availableCount ?? 0;
        return _DialogShell(
          icon: Icons.outgoing_mail,
          title: 'Assign keys',
          subtitle: widget.dealerName == null
              ? 'Send available keys to this dealer.'
              : 'Send available keys to ${widget.dealerName}.',
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed:
                  busy || snapshot.connectionState != ConnectionState.done
                  ? null
                  : () => submit(available),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(busy ? 'Assigning' : 'Assign keys'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SoftPanel(
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: AppTone.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$available keys currently available for assignment.',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              QuantityStepper(
                controller: quantity,
                label: 'Keys to assign',
                min: 1,
                max: available <= 0 ? 1 : available,
                onChanged: () => setState(() => error = null),
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
    required this.availableCount,
    required this.onAssigned,
  });
  final ApiClient api;
  final List<Map<String, dynamic>> dealers;
  final int availableCount;
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
        data: {'quantity': _quantity},
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
      setState(() => _step = 4);
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
          _WizardStepIndicator(step: _step, total: 5),
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
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
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
              onPressed: _quantity >= 1 && _quantity <= widget.availableCount
                  ? () => setState(() => _step = 3)
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Review'),
            ),
          ],
        ),
        3 => Row(
          children: [
            TextButton.icon(
              onPressed: _apiBusy
                  ? null
                  : () {
                      _holdController.reset();
                      _holdController.removeStatusListener(_onHoldStatus);
                      setState(() {
                        _step = 2;
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
        4 => Row(
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
          message:
              '${widget.availableCount} keys available in reseller stock.',
          tone: AppTone.info,
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 20),
        _LargeQuantityStepper(
          controller: _quantityController,
          min: 1,
          max: widget.availableCount <= 0 ? 1 : widget.availableCount,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [5, 10, 25, 50, 100]
              .where((v) => v <= widget.availableCount)
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

  // ── Step 3: Hold to Confirm ────────────────────────────────────────────────

  Widget _buildStep3() {
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
              _InfoRow('Keys', '$_quantity activation codes'),
              const SizedBox(height: 6),
              _InfoRow(
                'Stock after',
                '${widget.availableCount - _quantity} remaining',
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
        AnimatedBuilder(
          animation: _holdController,
          builder: (context, _) {
            return GestureDetector(
              onLongPressStart: _apiBusy || _holdComplete
                  ? null
                  : _onHoldStart,
              onLongPressEnd: (_) => _onHoldCancel(),
              onLongPressCancel: _onHoldCancel,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      height: 60,
                      color: AppTone.warning.withValues(alpha: 0.12),
                    ),
                    FractionallySizedBox(
                      widthFactor: _holdController.value,
                      child: Container(
                        height: 60,
                        color: AppTone.warning.withValues(alpha: 0.45),
                      ),
                    ),
                    SizedBox(
                      height: 60,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_apiBusy)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTone.warning,
                                ),
                              )
                            else
                              const Icon(
                                Icons.lock_outlined,
                                color: AppTone.warning,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _apiBusy ? 'Sending…' : 'Hold to send keys',
                              style: const TextStyle(
                                color: AppTone.warning,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
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
          },
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

  // ── Step 4: Success ────────────────────────────────────────────────────────

  Widget _buildStep4() {
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

class CreateDealerDialog extends StatefulWidget {
  const CreateDealerDialog({super.key, required this.api});
  final ApiClient api;

  @override
  State<CreateDealerDialog> createState() => _CreateDealerDialogState();
}

class _CreateDealerDialogState extends State<CreateDealerDialog> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final shop = TextEditingController();

  Future<void> submit() async {
    try {
      await widget.api.post(
        '/api/v1/auth/register/dealer',
        data: {
          'name': name.text,
          'email': email.text,
          'phone': phone.text,
          'shopName': shop.text,
          'password': 'Demo@123456',
        },
      );
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'Dealer created with temporary password Demo@123456');
      }
    } catch (e) {
      if (mounted) snack(context, readableError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Create dealer'),
    content: SizedBox(
      width: 520,
      child: Fields(
        children: [
          Input(name, 'Name'),
          Input(email, 'Email'),
          Input(phone, 'Phone'),
          Input(shop, 'Shop name'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Create')),
    ],
  );
}

class DataPage<T> extends StatefulWidget {
  const DataPage({
    super.key,
    required this.title,
    required this.loader,
    required this.builder,
    this.dealerId,
  });
  final String title;
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T, Future<void> Function()) builder;
  /// When provided, a successful load syncs device/key data to LocalVault.
  final String? dealerId;

  @override
  State<DataPage<T>> createState() => _DataPageState<T>();
}

class _DataPageState<T> extends State<DataPage<T>> {
  late Future<T> future = widget.loader();

  Future<void> reload() async {
    final next = widget.loader();
    setState(() => future = next);
    await next;
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
        // Successful load — sync to vault in background
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

class _PageState extends State<Page> {
  bool _refreshing = false;
  bool _atEnd = false;

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.reload!();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageChildren = <Widget>[
      _RefreshBanner(visible: _refreshing),
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
      _PageEndMark(visible: _atEnd),
    ];

    final scrollable = LayoutBuilder(
      builder: (context, constraints) =>
          NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollUpdateNotification) {
            final atEnd = n.metrics.extentAfter < 1.0;
            final pushingDown = (n.scrollDelta ?? 0) > 2.0;
            if (atEnd && pushingDown && !_atEnd) {
              setState(() => _atEnd = true);
              Future.delayed(
                const Duration(milliseconds: 1600),
                () {
                  if (mounted) setState(() => _atEnd = false);
                },
              );
            }
          }
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            constraints.maxWidth > 980 ? 28 : 16,
            constraints.maxWidth < 600 ? 72 : 18,
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

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppTone.brand,
      backgroundColor: AppTone.surface,
      strokeWidth: 2.5,
      displacement: 72,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      child: scrollable,
    );
  }
}

// ─── Page animation helpers ────────────────────────────────────────────────

/// Three staggered bouncing dots — shared by the refresh banner (top)
/// and the end-of-scroll marker (bottom).
class _BouncingDots extends StatelessWidget {
  const _BouncingDots({this.padding = const EdgeInsets.symmetric(vertical: 20)});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppTone.line,
                borderRadius: BorderRadius.circular(999),
              ),
            )
                .animate(
                  delay: (i * 110).ms,
                  onPlay: (c) => c.repeat(reverse: true),
                )
                .moveY(
                  begin: 0,
                  end: -5,
                  duration: 480.ms,
                  curve: Curves.easeInOut,
                ),
          );
        }),
      ),
    );
  }
}

class _RefreshBanner extends StatelessWidget {
  const _RefreshBanner({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _medium,
      curve: Curves.easeOutCubic,
      child: visible
          ? const _BouncingDots(
              padding: EdgeInsets.only(bottom: 14),
            )
              .animate()
              .fadeIn(duration: _fast)
              .slideY(begin: -0.4, end: 0, duration: _fast)
          : const SizedBox.shrink(),
    );
  }
}

class _PageEndMark extends StatelessWidget {
  const _PageEndMark({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _medium,
      curve: Curves.easeOutCubic,
      child: visible
          ? const _BouncingDots()
              .animate()
              .fadeIn(duration: _fast)
          : const SizedBox.shrink(),
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
                    Text(
                      '${widget.card.value ?? 0}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: color == AppTone.ink ? AppTone.ink : color,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
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
