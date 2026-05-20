import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../services/auth_service.dart';

/// Placeholder home screen. Will show EMI status, schedule, and payment info
/// once backend /api/v1/customer/devices/:imei and /api/v1/customer/schedule
/// endpoints are implemented.
class HomeScreen extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onSignedOut;

  const HomeScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onSignedOut,
  });

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(language);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111128),
        title: Text(s.homeTitle, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => onLanguageChanged(
              language == AppLanguage.bangla ? AppLanguage.english : AppLanguage.bangla,
            ),
            child: Text(
              s.langToggleLabel,
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF888888)),
            tooltip: s.homeSignOut,
            onPressed: _signOut,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, color: Color(0xFF1565C0), size: 64),
              const SizedBox(height: 24),
              Text(
                s.homeTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // TODO: Replace with real EMI status widget once backend is ready.
              // Required endpoints:
              //   GET /api/v1/customer/devices/:imei  — device + lock status
              //   GET /api/v1/customer/schedule       — upcoming EMI schedule
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A4A)),
                ),
                child: Text(
                  s.homeNotAvailable,
                  style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
