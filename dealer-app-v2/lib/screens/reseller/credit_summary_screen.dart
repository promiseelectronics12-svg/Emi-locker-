import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/widgets/tier_badge.dart';

class CreditSummaryScreen extends StatefulWidget {
  const CreditSummaryScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CreditSummaryScreen> createState() => _CreditSummaryScreenState();
}

class _CreditSummaryScreenState extends State<CreditSummaryScreen> {
  bool _loading = true;
  String _errorMsg = '';
  Map<String, dynamic>? _data;

  final _nidHashController = TextEditingController();
  bool _registering = false;
  bool _registerSuccess = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nidHashController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMsg = ''; });
    try {
      final res = await widget.api.get('/api/v1/reseller/credit/summary');
      setState(() { _data = asMap(res.data); _loading = false; });
    } catch (e) {
      setState(() { _errorMsg = readableError(e); _loading = false; });
    }
  }

  Future<void> _registerSeed() async {
    final hash = _nidHashController.text.trim();
    if (hash.length != 64) {
      snack(context, 'Enter a valid 64-character SHA-256 NID hash');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() { _registering = true; _registerSuccess = false; });
    try {
      await widget.api.post(
        '/api/v1/reseller/profiles/register-seed',
        data: {'nid_hash': hash},
      );
      if (mounted) {
        setState(() { _registering = false; _registerSuccess = true; });
        _nidHashController.clear();
        snack(context, 'Profile seed registered');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _registering = false);
        snack(context, readableError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit intelligence'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            SkeletonBox(width: double.infinity, height: 100),
            SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: 200),
          ],
        ),
      );
    }

    if (_errorMsg.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InlineNotice(
                  message: _errorMsg,
                  tone: AppTone.danger,
                  icon: Icons.error_outline),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }

    final d = _data!;
    final tiers = (d['tier_distribution'] as List? ?? [])
        .map((e) => asMap(e))
        .toList();
    final blacklistCount =
        (d['active_blacklist_count'] as num? ?? 0).toInt();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Blacklist stat card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: blacklistCount > 0
                ? AppTone.danger.withOpacity(0.06)
                : AppTone.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: blacklistCount > 0
                  ? AppTone.danger.withOpacity(0.3)
                  : AppTone.muted.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                blacklistCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                color: blacklistCount > 0 ? AppTone.danger : AppTone.brand,
                size: 28,
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active blacklist in region',
                      style: const TextStyle(
                          fontSize: 12, color: AppTone.muted)),
                  Text('$blacklistCount customers',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: blacklistCount > 0
                              ? AppTone.danger
                              : AppTone.ink)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Tier distribution',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 12),

        if (tiers.isEmpty)
          const Empty('No credit data yet for your region')
        else
          ...tiers.map((t) {
            final tier  = text(t['tier'], fallback: '—');
            final count = (t['count'] as num? ?? 0).toInt();
            final color = tierColor(tier);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  TierBadge(tier: tier),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: count > 0 ? (count / (count + 1)).clamp(0.0, 1.0) : 0.0,
                      backgroundColor: color.withOpacity(0.1),
                      color: color,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 36,
                    child: Text('$count',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTone.ink)),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 28),

        Text('Register profile seed',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 10),
        const InlineNotice(
          message:
              'Register that your Google Drive holds a backup for a customer profile.',
          tone: AppTone.info,
          icon: Icons.cloud_outlined,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nidHashController,
          decoration: const InputDecoration(
            labelText: 'NID hash (SHA-256)',
            hintText: '64-character hex string',
            prefixIcon: Icon(Icons.fingerprint_rounded),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          icon: _registering
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : (_registerSuccess
                  ? const Icon(Icons.check_rounded, size: 16)
                  : const Icon(Icons.cloud_upload_outlined, size: 16)),
          label: Text(_registerSuccess ? 'Registered!' : 'Register seed'),
          onPressed: _registering ? null : _registerSeed,
        ),
      ],
    );
  }
}
