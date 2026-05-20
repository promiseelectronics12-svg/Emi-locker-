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
  String? _errorCode;

  AppStrings get _s => AppStrings.of(widget.language);

  Future<void> _signIn({String? imei}) async {
    setState(() {
      _loading = true;
      _errorCode = null;
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

    // ACCOUNT_NOT_FOUND or DEVICE_NOT_ENROLLED → show IMEI dialog
    if (result.needsImei) {
      setState(() => _loading = false);
      await _showImeiDialog();
      return;
    }

    setState(() {
      _errorCode = result.errorCode;
      _loading = false;
    });
  }

  /// Validates that [imei] is exactly 15 digits.
  static bool _isValidImei(String imei) {
    final trimmed = imei.trim();
    return trimmed.length == 15 && RegExp(r'^\d{15}$').hasMatch(trimmed);
  }

  Future<void> _showImeiDialog() async {
    final s = _s;
    final controller = TextEditingController();
    String? fieldError;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text(
                s.imeiDialogTitle,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.imeiDialogInstruction,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    maxLength: 15,
                    style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1.5),
                    onChanged: (_) {
                      if (fieldError != null) setDialogState(() => fieldError = null);
                    },
                    decoration: InputDecoration(
                      hintText: s.imeiDialogHint,
                      hintStyle: const TextStyle(color: Color(0xFF444455), letterSpacing: 0),
                      counterStyle: const TextStyle(color: Color(0xFF555566), fontSize: 11),
                      errorText: fieldError,
                      errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF1565C0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
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
                  child: Text(s.imeiDialogCancel, style: const TextStyle(color: Color(0xFF888888))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    final v = controller.text.trim();
                    if (!_isValidImei(v)) {
                      setDialogState(() => fieldError = s.imeiInvalidError);
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(s.imeiDialogContinue, style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true) {
      final imei = controller.text.trim();
      if (_isValidImei(imei)) {
        await _signIn(imei: imei);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;

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

              if (_errorCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B0A0A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.errorForCode(_errorCode!),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
