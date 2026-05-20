import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/l10n.dart';
import 'screens/disclosure_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AuthService.instance.init();
  await FcmService.instance.init();
  runApp(const EmiLockerApp());
}

class EmiLockerApp extends StatefulWidget {
  const EmiLockerApp({super.key});

  @override
  State<EmiLockerApp> createState() => _EmiLockerAppState();
}

class _EmiLockerAppState extends State<EmiLockerApp> {
  AppLanguage _language = AppLanguage.bangla;
  bool? _disclosureAccepted;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('app_language') ?? 'bn';
    setState(() {
      _language = langCode == 'en' ? AppLanguage.english : AppLanguage.bangla;
      _disclosureAccepted = prefs.getBool('disclosure_accepted') ?? false;
      _initialized = true;
    });
  }

  Future<void> _setLanguage(AppLanguage lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', lang.locale.languageCode);
    setState(() => _language = lang);
  }

  void _onDisclosureAgreed() => setState(() => _disclosureAccepted = true);
  void _onAuthenticated() => setState(() {});
  void _onSignedOut() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EMI Locker',
      debugShowCheckedModeBanner: false,
      locale: _language.locale,
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1565C0),
          secondary: Color(0xFF4FC3F7),
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF1565C0)),
        ),
      );
    }

    if (_disclosureAccepted != true) {
      return DisclosureScreen(
        language: _language,
        onLanguageChanged: _setLanguage,
        onAgreed: _onDisclosureAgreed,
      );
    }

    if (!AuthService.instance.isAuthenticated) {
      return LoginScreen(
        language: _language,
        onLanguageChanged: _setLanguage,
        onAuthenticated: _onAuthenticated,
      );
    }

    return HomeScreen(
      language: _language,
      onLanguageChanged: _setLanguage,
      onSignedOut: _onSignedOut,
    );
  }
}
