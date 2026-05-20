import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onAuthenticated;

  const LoginScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onAuthenticated,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _errorMsg;

  Future<void> _signIn({String? imei}) async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final result = await AuthService.instance.signInWithGoogle(imei: imei);

    if (!mounted) return;

    if (result.success) {
      widget.onAuthenticated();
      return;
    }

    if (result.cancelled) {
      setState(() => _loading = false);
      return;
    }

    // Fix 2: ACCOUNT_NOT_FOUND → prompt user for IMEI to bind device on first sign-in.
    // (Normal Android apps cannot reliably read IMEI; AIDL bridge comes in Stream D.)
    if (result.error?.contains('IMEI') == true ||
        result.error?.contains('not found') == true ||
        result.error?.contains('not enrolled') == true) {
      setState(() => _loading = false);
      await _showImeiDialog();
      return;
    }

    setState(() {
      _errorMsg = result.error;
      _loading = false;
    });
  }

  Future<void> _showImeiDialog() async {
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: const Text(
            'Enter Device IMEI',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'First sign-in requires your device IMEI to verify enrollment.\n\nDial *#06# to find your IMEI.',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 17,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '15-digit IMEI',
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  counterStyle: const TextStyle(color: Color(0xFF555555)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF1565C0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0A0A1A),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF888888))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      await _signIn(imei: controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(widget.language);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => widget.onLanguageChanged(
                    widget.language == AppLanguage.bangla
                        ? AppLanguage.english
                        : AppLanguage.bangla,
                  ),
                  child: Text(
                    s.langToggleLabel,
                    style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 13),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.shield, color: Colors.white, size: 44),
              ),

              const SizedBox(height: 24),

              Text(
                s.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                s.loginSubtitle,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 15),
              ),

              const Spacer(flex: 3),

              if (_errorMsg != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B0A0A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMsg!,
                    style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : () => _signIn(),
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login, color: Colors.white),
                  label: Text(
                    _loading ? s.loginLoading : s.loginButton,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A73E8),
                    disabledBackgroundColor: const Color(0xFF1A3A5C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
