import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/biometric_service.dart';

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({
    super.key,
    required this.onAuthenticated,
    this.onUsePassword,
  });

  final VoidCallback onAuthenticated;
  /// Called when user chooses to fall back to full email+password login.
  final VoidCallback? onUsePassword;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _busy = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    setState(() { _busy = true; _errorMsg = ''; });
    try {
      final success = await BiometricService().authenticate(
        reason: 'Verify your identity to continue',
      );
      if (success && mounted) {
        widget.onAuthenticated();
      } else if (mounted) {
        setState(() { _busy = false; _errorMsg = 'Authentication failed. Try again.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _busy = false; _errorMsg = readableError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTone.brand.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fingerprint_rounded,
                    color: AppTone.brand, size: 44),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Verify your identity to continue',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 40),

              if (_busy)
                const CircularProgressIndicator(color: AppTone.brand)
              else ...[
                if (_errorMsg.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTone.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTone.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTone.danger, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMsg,
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                FilledButton.icon(
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Unlock with biometric / PIN'),
                  onPressed: _authenticate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppTone.brand,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onUsePassword,
                  child: const Text(
                    'Use password instead',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps any widget with a biometric gate that activates on app resume.
class AppBiometricGate extends StatefulWidget {
  const AppBiometricGate({
    super.key,
    required this.child,
    this.onUsePassword,
  });

  final Widget child;
  /// Called when user taps "Use password instead" — parent clears session.
  final VoidCallback? onUsePassword;

  @override
  State<AppBiometricGate> createState() => _AppBiometricGateState();
}

class _AppBiometricGateState extends State<AppBiometricGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBiometric();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkBiometric() async {
    final enabled = await BiometricService().isBiometricEnabled();
    if (mounted) setState(() { _biometricEnabled = enabled; _locked = enabled; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _biometricEnabled) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return BiometricLockScreen(
        onAuthenticated: () => setState(() => _locked = false),
        onUsePassword: widget.onUsePassword,
      );
    }
    return widget.child;
  }
}
