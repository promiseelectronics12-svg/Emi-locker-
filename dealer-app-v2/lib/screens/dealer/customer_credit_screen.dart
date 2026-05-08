import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/widgets/credit_score_gauge.dart';
import 'package:dealer_app/widgets/tier_badge.dart';

class CustomerCreditScreen extends StatefulWidget {
  const CustomerCreditScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CustomerCreditScreen> createState() => _CustomerCreditScreenState();
}

class _CustomerCreditScreenState extends State<CustomerCreditScreen> {
  final _hashController = TextEditingController();
  bool _rawMode = false; // false = enter NID hash directly, true = enter raw NID
  bool _loading = false;
  Map<String, dynamic>? _result;
  String _errorMsg = '';
  bool _searched = false;

  @override
  void dispose() {
    _hashController.dispose();
    super.dispose();
  }

  String _sha256hex(String input) {
    final bytes = Uint8List.fromList(input.codeUnits);
    final digest = SHA256Digest().process(bytes);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _lookup() async {
    final raw = _hashController.text.trim();
    if (raw.isEmpty) return;

    final nidHash = _rawMode ? _sha256hex(raw) : raw;

    if (!_rawMode && nidHash.length != 64) {
      setState(() => _errorMsg = 'NID hash must be 64 hex characters (SHA-256).');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() { _loading = true; _errorMsg = ''; _result = null; _searched = true; });

    try {
      final res = await widget.api.post(
        '/api/v1/dealer/customer/lookup',
        data: {'nid_hash': nidHash},
      );
      setState(() {
        _result = asMap(res.data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = readableError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer credit check')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Mode toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: Icon(_rawMode ? Icons.tag_rounded : Icons.person_outline_rounded,
                    size: 14),
                label: Text(_rawMode ? 'Enter hash directly' : 'Enter raw NID'),
                onPressed: () {
                  setState(() {
                    _rawMode = !_rawMode;
                    _hashController.clear();
                    _result = null;
                    _errorMsg = '';
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 4),

          TextField(
            controller: _hashController,
            decoration: InputDecoration(
              labelText: _rawMode ? 'National ID number' : 'NID hash (SHA-256)',
              hintText: _rawMode ? 'e.g. 1990-1234567' : '64-character hex string',
              prefixIcon: Icon(_rawMode
                  ? Icons.badge_outlined
                  : Icons.fingerprint_rounded),
            ),
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: _loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search_rounded),
            label: const Text('Check credit'),
            onPressed: _loading ? null : _lookup,
          ),

          if (_errorMsg.isNotEmpty) ...[
            const SizedBox(height: 16),
            InlineNotice(
                message: _errorMsg,
                tone: AppTone.danger,
                icon: Icons.error_outline),
          ],

          if (_result != null) ...[
            const SizedBox(height: 28),
            _CreditResultPanel(data: _result!),
          ],

          if (_searched && !_loading && _result == null && _errorMsg.isEmpty) ...[
            const SizedBox(height: 28),
            const InlineNotice(
              message:
                  'First-time customer — no credit history recorded. Proceed with standard enrollment.',
              tone: AppTone.warning,
              icon: Icons.info_outline_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditResultPanel extends StatelessWidget {
  const _CreditResultPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final score  = (data['score'] as num? ?? 0).toInt();
    final tier   = text(data['tier'], fallback: 'BRONZE');
    final stats  = asMap(data['stats']);

    final paymentRate    = text(stats['payment_rate'], fallback: '—');
    final completed      = text(stats['devices_completed'], fallback: '0');
    final onTime         = text(stats['on_time'], fallback: '0');
    final late           = text(stats['late'], fallback: '0');
    final missed         = text(stats['missed'], fallback: '0');

    final isBlacklisted = tier.toUpperCase() == 'BLACKLISTED';
    final isRed         = tier.toUpperCase() == 'RED';
    final isGold        = tier.toUpperCase() == 'GOLD';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CreditScoreGauge(score: score, tier: tier),
        const SizedBox(height: 20),

        if (isBlacklisted || isRed)
          const InlineNotice(
            message:
                'This customer is flagged. Proceed with extreme caution.',
            tone: AppTone.danger,
            icon: Icons.warning_amber_rounded,
          )
        else if (isGold)
          const InlineNotice(
            message: 'Excellent credit history. Trusted customer.',
            tone: AppTone.brand,
            icon: Icons.verified_rounded,
          ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTone.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTone.muted.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              _StatRow('Payment rate', paymentRate),
              _StatRow('Devices completed', completed),
              _StatRow('On-time payments', onTime),
              _StatRow('Late payments', late),
              _StatRow('Missed payments', missed),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppTone.muted)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTone.ink)),
        ],
      ),
    );
  }
}
