import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/l10n.dart';

class DisclosureScreen extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onAgreed;

  const DisclosureScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onAgreed,
  });

  Future<void> _agree(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('disclosure_accepted', true);
    onAgreed();
  }

  void _decline(BuildContext context, AppStrings s) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(s.disclosureDeclineWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(language);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Language toggle
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => onLanguageChanged(
                    language == AppLanguage.bangla
                        ? AppLanguage.english
                        : AppLanguage.bangla,
                  ),
                  child: Text(
                    s.langToggleLabel,
                    style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // App logo + title
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1565C0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shield, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.appName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Text(
                s.disclosureTitle,
                style: const TextStyle(
                  color: Color(0xFF4FC3F7),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                s.disclosureIntro,
                style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14, height: 1.5),
              ),

              const SizedBox(height: 16),

              // Disclosure bullets
              ...s.disclosureBullets.map(
                (bullet) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 14)),
                      Expanded(
                        child: Text(
                          bullet,
                          style: const TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Action buttons
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _agree(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    s.disclosureAgree,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => _decline(context, s),
                  child: Text(
                    s.disclosureDecline,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
