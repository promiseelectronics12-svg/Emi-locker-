import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

class FraudCenterScreen extends StatefulWidget {
  const FraudCenterScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<FraudCenterScreen> createState() => _FraudCenterScreenState();
}

class _FraudCenterScreenState extends State<FraudCenterScreen> {
  bool _loading = true;
  String _errorMsg = '';
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMsg = ''; });
    try {
      final res = await widget.api.get('/api/v1/alerts');
      final data = asMap(res.data);
      final list = (data['alerts'] as List? ?? [])
          .map((e) => asMap(e))
          .toList();
      setState(() { _alerts = list; _loading = false; });
    } catch (e) {
      setState(() { _errorMsg = readableError(e); _loading = false; });
    }
  }

  int _countType(String type) =>
      _alerts.where((a) => text(a['alert_type']) == type).length;

  int get _openCount =>
      _alerts.where((a) => text(a['status']) != 'resolved').length;

  List<Map<String, dynamic>> get _anomalies => _alerts
      .where((a) {
        final t = text(a['alert_type']);
        return t.contains('LOCATION') ||
            t.contains('TRAVEL') ||
            t.contains('REGION') ||
            t.contains('RELOCATION');
      })
      .toList();

  List<Map<String, dynamic>> get _simAlerts =>
      _alerts.where((a) => text(a['alert_type']).contains('SIM')).toList();

  List<Map<String, dynamic>> get _theftAlerts =>
      _alerts.where((a) => text(a['alert_type']).contains('THEFT')).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fraud center'),
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
            SkeletonBox(width: double.infinity, height: 80),
            SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: 120),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 120),
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

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Overview stats
        StatGrid(cards: [
          StatCard('Open alerts',    _openCount,
              color: _openCount > 0 ? AppTone.danger : AppTone.brand),
          StatCard('SIM events',     _simAlerts.length,
              color: AppTone.warning),
          StatCard('Location anomalies', _anomalies.length,
              color: AppTone.accent),
          StatCard('Theft captures', _theftAlerts.length,
              color: AppTone.ink),
        ]),
        const SizedBox(height: 24),

        // Location anomalies
        if (_anomalies.isNotEmpty) ...[
          Text('Location anomalies',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTone.muted)),
          const SizedBox(height: 10),
          ..._anomalies.map((a) => _AnomalyTile(alert: a, api: widget.api)),
          const SizedBox(height: 20),
        ],

        // SIM events
        if (_simAlerts.isNotEmpty) ...[
          Text('SIM change events',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTone.muted)),
          const SizedBox(height: 10),
          ..._simAlerts.map((a) => _AlertTile(alert: a)),
          const SizedBox(height: 20),
        ],

        // Theft captures
        if (_theftAlerts.isNotEmpty) ...[
          Text('Theft captures',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTone.muted)),
          const SizedBox(height: 10),
          ..._theftAlerts.map((a) => _TheftTile(alert: a, api: widget.api)),
          const SizedBox(height: 20),
        ],

        if (_alerts.isEmpty)
          const Empty('No alerts — all clear'),
      ],
    );
  }
}

class _AnomalyTile extends StatefulWidget {
  const _AnomalyTile({required this.alert, required this.api});

  final Map<String, dynamic> alert;
  final ApiClient api;

  @override
  State<_AnomalyTile> createState() => _AnomalyTileState();
}

class _AnomalyTileState extends State<_AnomalyTile> {
  bool _revealing = false;
  String? _coords;

  Future<void> _revealLocation() async {
    final alert  = widget.alert;
    final deviceId = text(alert['device_id']);
    final alertId  = text(alert['id']);

    final reason = await _ReasonDialog.show(context);
    if (reason == null || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _revealing = true);
    try {
      final res = await widget.api.post(
        '/api/v1/dealer/devices/$deviceId/anomalies/$alertId/reveal',
        data: {'reason': reason},
      );
      final data = asMap(res.data);
      final lat = data['lat'];
      final lon = data['lon'];
      if (mounted) {
        setState(() {
          _coords = lat != null && lon != null ? '$lat, $lon' : 'Coordinates unavailable';
          _revealing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _revealing = false);
        snack(context, readableError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a    = widget.alert;
    final type = text(a['alert_type'], fallback: 'ANOMALY');
    final area = text(a['area_description'], fallback: 'Unknown area');
    final conf = text(a['confidence'], fallback: '');
    final ts   = text(a['created_at'], fallback: '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTone.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTone.muted.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTone.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(type,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTone.accent)),
              ),
              const Spacer(),
              if (conf.isNotEmpty)
                Text('Confidence: $conf',
                    style: const TextStyle(
                        fontSize: 10, color: AppTone.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(area, style: const TextStyle(fontSize: 13, color: AppTone.ink)),
          if (ts.isNotEmpty)
            Text(ts, style: const TextStyle(fontSize: 11, color: AppTone.muted)),
          if (_coords != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTone.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppTone.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_coords!,
                        style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 12,
                            color: AppTone.accent)),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.copy_outlined,
                        size: 14, color: AppTone.muted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _coords!));
                      snack(context, 'Coordinates copied');
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _revealing
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.location_searching_rounded, size: 14),
              label: const Text('Reveal location'),
              onPressed: _revealing ? null : _revealLocation,
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final Map<String, dynamic> alert;

  @override
  Widget build(BuildContext context) {
    final type     = text(alert['alert_type'], fallback: 'ALERT');
    final severity = text(alert['severity'], fallback: '');
    final ts       = text(alert['created_at'], fallback: '');
    final isCrit   = severity == 'CRITICAL';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCrit ? AppTone.danger.withOpacity(0.04) : AppTone.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCrit
              ? AppTone.danger.withOpacity(0.3)
              : AppTone.muted.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sim_card_alert_outlined,
            size: 18,
            color: isCrit ? AppTone.danger : AppTone.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                if (ts.isNotEmpty)
                  Text(ts,
                      style: const TextStyle(
                          fontSize: 11, color: AppTone.muted)),
              ],
            ),
          ),
          if (isCrit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTone.danger,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('CRITICAL',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

class _TheftTile extends StatefulWidget {
  const _TheftTile({required this.alert, required this.api});

  final Map<String, dynamic> alert;
  final ApiClient api;

  @override
  State<_TheftTile> createState() => _TheftTileState();
}

class _TheftTileState extends State<_TheftTile> {
  bool _requesting = false;
  bool _requested = false;

  Future<void> _requestEvidenceAccess() async {
    final deviceId = text(widget.alert['device_id']);
    setState(() => _requesting = true);
    try {
      await widget.api.post(
        '/api/v1/evidence/access-request',
        data: {'device_id': deviceId},
      );
      if (mounted) setState(() { _requesting = false; _requested = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _requesting = false);
        snack(context, readableError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = text(widget.alert['created_at'], fallback: '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTone.danger.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTone.danger.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_outlined,
                  size: 18, color: AppTone.danger),
              const SizedBox(width: 8),
              const Text('Theft capture',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppTone.danger)),
            ],
          ),
          if (ts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(ts, style: const TextStyle(fontSize: 11, color: AppTone.muted)),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 80,
            decoration: BoxDecoration(
              color: AppTone.muted.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTone.muted.withOpacity(0.15)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, color: AppTone.muted, size: 24),
                SizedBox(height: 4),
                Text('Photo encrypted',
                    style: TextStyle(fontSize: 11, color: AppTone.muted)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_requested)
            const InlineNotice(
              message: 'Access request submitted — pending admin approval.',
              tone: AppTone.warning,
              icon: Icons.hourglass_top_rounded,
            )
          else
            OutlinedButton.icon(
              icon: _requesting
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open_outlined, size: 14),
              label: const Text('Request evidence access'),
              onPressed: _requesting ? null : _requestEvidenceAccess,
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }
}

class _ReasonDialog {
  static Future<String?> show(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reveal location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revealing coordinates is permanently logged. State a reason:',
              style: TextStyle(fontSize: 13, color: AppTone.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Customer reported device stolen',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final r = controller.text.trim();
                if (r.isEmpty) return;
                Navigator.pop(ctx, r);
              },
              child: const Text('Reveal')),
        ],
      ),
    );
  }
}
