import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/sse_service.dart';
import 'unlock_flow_screen.dart';

class LockDetailScreen extends StatefulWidget {
  const LockDetailScreen({
    super.key,
    required this.api,
    required this.deviceId,
    required this.deviceName,
  });

  final ApiClient api;
  final String deviceId;
  final String deviceName;

  @override
  State<LockDetailScreen> createState() => _LockDetailScreenState();
}

class _LockDetailScreenState extends State<LockDetailScreen> {
  bool _loading = true;
  String _errorMsg = '';
  Map<String, dynamic>? _detail;
  Timer? _ticker;
  Duration _graceRemaining = Duration.zero;
  StreamSubscription<SseEvent>? _sseSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream != null) {
      _sseSub = stream.listen((event) {
        if (!mounted) return;
        final eventDeviceId = event.data['deviceId']?.toString() ?? event.data['id']?.toString();
        if (eventDeviceId == widget.deviceId &&
            (event.type == 'device_locked' || event.type == 'device_unlocked' || event.type == 'grace_expired')) {
          _load();
        }
      });
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMsg = ''; });
    try {
      final res = await widget.api.get(
          '/api/v1/dealer/devices/${widget.deviceId}/lock-detail');
      final d = asMap(res.data);
      setState(() {
        _detail = d;
        _loading = false;
      });
      _startGraceTimer(d);
    } catch (e) {
      setState(() {
        _errorMsg = readableError(e);
        _loading = false;
      });
    }
  }

  void _startGraceTimer(Map<String, dynamic> d) {
    final expiresStr = text(d['active_grace']?['expires_at']);
    if (expiresStr.isEmpty) return;
    final expires = DateTime.tryParse(expiresStr);
    if (expires == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      final rem = expires.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _graceRemaining = rem.isNegative ? Duration.zero : rem);
    });
    final rem = expires.difference(DateTime.now());
    setState(() => _graceRemaining = rem.isNegative ? Duration.zero : rem);
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return 'Expired';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$h hours $m minutes';
    return '$m minutes';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: double.infinity, height: 100),
            SizedBox(height: 16),
            SkeletonBox(width: double.infinity, height: 60),
            SizedBox(height: 12),
            SkeletonBox(width: double.infinity, height: 60),
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

    final d = _detail!;
    final lockLevel    = text(d['lock_level'], fallback: '—');
    final lockReason   = text(d['lock_reason'], fallback: 'No reason provided');
    final lockedAt     = text(d['locked_at']);
    final graceExpAt   = text(d['grace_expires_at']);
    final lastCheckin  = text(d['last_checkin_at']);
    final activeGrace  = d['active_grace'];
    final history      = d['history'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Lock status card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTone.danger.withOpacity(0.04),
            border: Border(left: BorderSide(color: AppTone.danger, width: 4)),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, color: AppTone.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Lock level $lockLevel',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: AppTone.danger)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_humanReason(lockReason),
                  style: const TextStyle(fontSize: 13, color: AppTone.ink)),
              if (lockedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Locked at: $lockedAt',
                    style: const TextStyle(fontSize: 11, color: AppTone.muted)),
              ],
              if (graceExpAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Grace expires: $graceExpAt',
                    style: const TextStyle(fontSize: 11, color: AppTone.muted)),
              ],
              if (lastCheckin.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Last check-in: $lastCheckin',
                    style: const TextStyle(fontSize: 11, color: AppTone.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Active grace countdown
        if (activeGrace != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTone.brand.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTone.brand.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_open_outlined,
                        color: AppTone.brand, size: 16),
                    const SizedBox(width: 8),
                    const Text('Grace period active',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: AppTone.brand)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _graceRemaining.inSeconds > 0
                      ? _graceRemaining.inSeconds /
                          (int.tryParse(
                                      text(activeGrace['grace_hours'])) ??
                                  8) /
                              3600
                      : 0.0,
                  backgroundColor: AppTone.brand.withOpacity(0.15),
                  color: AppTone.brand,
                ),
                const SizedBox(height: 6),
                Text('Remaining: ${_formatDuration(_graceRemaining)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTone.muted)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Unlock device'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UnlockFlowScreen(
                      api: widget.api,
                      deviceId: widget.deviceId,
                      deviceName: widget.deviceName,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Lock history
        if (history.isNotEmpty) ...[
          Text('Recent events',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AppTone.muted)),
          const SizedBox(height: 10),
          ...history.take(5).map((e) {
            final ev = asMap(e);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: const BoxDecoration(
                      color: AppTone.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text(ev['event_type'], fallback: 'Event'),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppTone.ink)),
                        Text(text(ev['created_at'], fallback: ''),
                            style: const TextStyle(
                                fontSize: 11, color: AppTone.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _humanReason(String raw) {
    switch (raw) {
      case 'MISSED_PAYMENT': return 'Missed payment';
      case 'LATE_PAYMENT':   return 'Late payment';
      case 'MANUAL_LOCK':    return 'Manually locked by dealer';
      case 'FRAUD_ALERT':    return 'Fraud alert triggered';
      default:               return raw;
    }
  }
}
