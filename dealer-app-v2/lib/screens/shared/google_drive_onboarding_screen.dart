import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/google_vault.dart';

class GoogleDriveOnboardingScreen extends StatefulWidget {
  const GoogleDriveOnboardingScreen({super.key});

  @override
  State<GoogleDriveOnboardingScreen> createState() =>
      _GoogleDriveOnboardingScreenState();
}

class _GoogleDriveOnboardingScreenState
    extends State<GoogleDriveOnboardingScreen> {
  bool _loading = true;
  bool _isBound = false;
  String _boundEmail = '';

  final _checks = [false, false, false, false];
  bool _binding = false;

  static const _checkLabels = [
    'My encrypted evidence photos will be backed up to Google Drive',
    'Only I can decrypt them — the server cannot read the raw photos',
    'Disconnecting stops new backups but existing Drive files remain',
    'I can revoke access anytime from Google Account settings',
  ];

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _loading = true);
    final bound = await GoogleVault.isBound();
    final email = await GoogleVault.boundEmail() ?? '';
    if (mounted) {
      setState(() {
        _isBound = bound;
        _boundEmail = email;
        _loading = false;
      });
    }
  }

  Future<void> _connect() async {
    HapticFeedback.lightImpact();
    setState(() => _binding = true);
    final success = await GoogleVault.bind();
    if (!mounted) return;
    if (success) {
      await _checkStatus();
      snack(context, 'Google Drive connected');
    } else {
      setState(() => _binding = false);
      snack(context, 'Connection cancelled or failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _isBound
              ? _BoundState(
                  email: _boundEmail,
                  onDisconnect: () async {
                    // Disconnect = clear stored email; user must revoke via Google
                    await GoogleVault.bind(); // re-triggers sign in; no sign-out API
                    snack(context,
                        'To fully disconnect, revoke access in Google Account settings.');
                  },
                )
              : _UnboundState(
                  checks: _checks,
                  onCheckChanged: (i, v) =>
                      setState(() => _checks[i] = v),
                  checkLabels: _checkLabels,
                  allChecked: _checks.every((c) => c),
                  binding: _binding,
                  onConnect: _connect,
                ),
    );
  }
}

class _UnboundState extends StatelessWidget {
  const _UnboundState({
    required this.checks,
    required this.onCheckChanged,
    required this.checkLabels,
    required this.allChecked,
    required this.binding,
    required this.onConnect,
  });

  final List<bool> checks;
  final void Function(int, bool) onCheckChanged;
  final List<String> checkLabels;
  final bool allChecked;
  final bool binding;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTone.info.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTone.info.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cloud_outlined, color: AppTone.info, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Encrypted backup',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppTone.info),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your evidence photos are encrypted on-device before upload. '
                      'Google cannot see the contents. '
                      'Backups survive app reinstalls.',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTone.info.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Before connecting, please confirm:',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 10),

        ...List.generate(checkLabels.length, (i) {
          return CheckboxListTile(
            value: checks[i],
            onChanged: (v) => onCheckChanged(i, v ?? false),
            title: Text(checkLabels[i],
                style: const TextStyle(fontSize: 13, color: AppTone.ink)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: AppTone.info,
          );
        }),

        const SizedBox(height: 24),
        FilledButton.icon(
          icon: binding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_link_rounded, size: 16),
          label: const Text('Connect Google Drive'),
          onPressed: allChecked && !binding ? onConnect : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppTone.info,
          ),
        ),
        if (!allChecked) ...[
          const SizedBox(height: 8),
          const Text(
            'Check all boxes above to proceed.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTone.muted),
          ),
        ],
      ],
    );
  }
}

class _BoundState extends StatelessWidget {
  const _BoundState({required this.email, required this.onDisconnect});

  final String email;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppTone.brand, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Connected',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTone.ink)),
          const SizedBox(height: 8),
          Text(email,
              style: const TextStyle(
                  color: AppTone.muted,
                  fontSize: 14)),
          const SizedBox(height: 8),
          const Text(
            'Encrypted evidence photos are backed up to this account\'s '
            'hidden app-data folder.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTone.muted),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: onDisconnect,
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTone.danger,
                side: BorderSide(color: AppTone.danger.withValues(alpha: 0.5))),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}
