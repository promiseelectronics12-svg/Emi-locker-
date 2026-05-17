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
  Timer? _sseDebounce;
  Duration _graceRemaining = Duration.zero;
  StreamSubscription<SseEvent>? _sseSub;

  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = false;
  String _historyFilter = 'all';

  List<Map<String, dynamic>> _locations = [];
  bool _locationsLoading = false;

  static const _refreshEvents = {
    'device_locked',
    'device_unlocked',
    'device_unlock_pending',
    'grace_expired',
    'device_online',
    'device_offline',
    'device_status_changed',
    'device_runtime_updated',
    'sim_changed',
    'fraud_suspected',
    'sms_heartbeat',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
    _loadLocations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sseSub?.cancel();
    final stream = AppEventScope.of(context);
    if (stream != null) {
      _sseSub = stream.listen((event) {
        if (!mounted) return;
        final eventDeviceId = _eventDeviceId(event.data);
        if (eventDeviceId == widget.deviceId &&
            _refreshEvents.contains(event.type)) {
          _scheduleSilentReload();
        }
      });
    }
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    _sseDebounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _eventDeviceId(Map<String, dynamic> data) {
    final nestedDevice = data['device'];
    if (nestedDevice is Map) {
      final nestedId =
          nestedDevice['id'] ??
          nestedDevice['deviceId'] ??
          nestedDevice['device_id'];
      if (nestedId != null) return nestedId.toString();
    }
    return (data['deviceId'] ?? data['device_id'] ?? data['id'] ?? '')
        .toString();
  }

  void _scheduleSilentReload() {
    _sseDebounce?.cancel();
    _sseDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        _load(silent: true);
        _loadHistory(silent: true);
        _loadLocations();
      }
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _errorMsg = '';
      });
    }
    try {
      final res = await widget.api.get(
        '/api/v1/dealer/devices/${widget.deviceId}/lock-detail',
      );
      final d = asMap(res.data);
      setState(() {
        _detail = d;
        _loading = false;
        _errorMsg = '';
      });
      _startGraceTimer(d);
    } catch (e) {
      if (!silent) {
        setState(() {
          _errorMsg = readableError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (!silent) setState(() => _historyLoading = true);
    try {
      final typeParam = _historyFilter == 'all' ? '' : '&type=$_historyFilter';
      final res = await widget.api.get(
        '/api/v1/dealer/devices/${widget.deviceId}/history?limit=50$typeParam',
      );
      final data = res.data;
      final list = (data is Map ? data['history'] : null) as List? ?? [];
      if (mounted) {
        setState(() {
          _history = list.map((e) => asMap(e)).toList();
          _historyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _loadLocations() async {
    setState(() => _locationsLoading = true);
    try {
      final res = await widget.api.get(
        '/api/v1/dealer/devices/${widget.deviceId}/locations?limit=30',
      );
      final data = res.data;
      final list = (data is Map ? data['locations'] : null) as List? ?? [];
      if (mounted) {
        setState(() {
          _locations = list.map((e) => asMap(e)).toList();
          _locationsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationsLoading = false);
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
            onPressed: () {
              _load();
              _loadHistory();
              _loadLocations();
            },
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
                icon: Icons.error_outline,
              ),
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
    final lock = asMap(d['lock']);
    final emi = asMap(d['emi']);
    final lockLevel = text(lock['lock_level'], fallback: 'NONE');
    final isLocked = lock['is_locked'] == true;
    final lockReason = text(lock['reason'], fallback: 'No reason provided');
    final lockedAt = text(lock['locked_at']);
    final graceExpAt = text(lock['grace_expires_at'] ?? d['grace_expires_at']);
    final lastCheckin = text(d['last_checkin_at']);
    final emiPaid = text(emi['installments_paid'], fallback: '0');
    final emiTotal = text(emi['installments_total'], fallback: '0');
    final emiLinked = emiTotal != '0';
    final activeGrace = d['active_grace'];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Lock status card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (isLocked ? AppTone.danger : AppTone.brand).withValues(alpha: 0.04),
            border: Border(
              left: BorderSide(
                color: isLocked ? AppTone.danger : AppTone.brand,
                width: 4,
              ),
            ),
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
                  Icon(
                    isLocked ? Icons.lock_outline : Icons.lock_open_rounded,
                    color: isLocked ? AppTone.danger : AppTone.brand,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLocked ? 'Device locked' : 'Device unlocked',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isLocked ? AppTone.danger : AppTone.brand,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: lockLevel,
                    color: isLocked ? AppTone.danger : AppTone.brand,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                isLocked
                    ? _humanReason(lockReason)
                    : 'No active lock is applied.',
                style: const TextStyle(fontSize: 13, color: AppTone.ink),
              ),
              if (lockedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Locked at: $lockedAt',
                  style: const TextStyle(fontSize: 11, color: AppTone.muted),
                ),
              ],
              if (graceExpAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Grace expires: $graceExpAt',
                  style: const TextStyle(fontSize: 11, color: AppTone.muted),
                ),
              ],
              if (lastCheckin.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Last check-in: $lastCheckin',
                  style: const TextStyle(fontSize: 11, color: AppTone.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // EMI row
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTone.info.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTone.info.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              const Icon(Icons.payments_outlined, size: 18, color: AppTone.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  emiLinked
                      ? 'EMI schedule linked: $emiPaid of $emiTotal installments paid'
                      : 'EMI schedule not linked for this device',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTone.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Active grace countdown
        if (activeGrace != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTone.brand.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_open_outlined, color: AppTone.brand, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Grace period active',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.brand),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _graceRemaining.inSeconds > 0
                      ? _graceRemaining.inSeconds /
                            (int.tryParse(text(activeGrace['grace_hours'])) ?? 8) /
                            3600
                      : 0.0,
                  backgroundColor: AppTone.brand.withValues(alpha: 0.15),
                  color: AppTone.brand,
                ),
                const SizedBox(height: 6),
                Text(
                  'Remaining: ${_formatDuration(_graceRemaining)}',
                  style: const TextStyle(fontSize: 12, color: AppTone.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Unlock action
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
        const SizedBox(height: 24),

        // ── Event History ──────────────────────────────────────────────────
        _SectionHeader(
          title: 'Event history',
          loading: _historyLoading,
          onRefresh: _loadHistory,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in const [
                ('all', 'All'),
                ('lock', 'Lock'),
                ('sim', 'SIM'),
                ('calls', 'Calls'),
                ('fraud', 'Fraud'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(f.$2),
                    selected: _historyFilter == f.$1,
                    onSelected: (_) {
                      setState(() => _historyFilter = f.$1);
                      _loadHistory();
                    },
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _historyFilter == f.$1 ? Colors.white : AppTone.muted,
                    ),
                    selectedColor: AppTone.brand,
                    backgroundColor: AppTone.page,
                    showCheckmark: false,
                    side: BorderSide(
                      color: _historyFilter == f.$1
                          ? AppTone.brand
                          : AppTone.line,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (_historyLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No events recorded yet.',
              style: const TextStyle(fontSize: 13, color: AppTone.muted),
            ),
          )
        else
          ..._history.map((e) => _HistoryEventRow(event: e)),
        const SizedBox(height: 24),

        // ── Location History ───────────────────────────────────────────────
        _SectionHeader(
          title: 'Location history',
          loading: _locationsLoading,
          onRefresh: _loadLocations,
        ),
        const SizedBox(height: 10),
        if (_locationsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_locations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No location data recorded yet.',
              style: TextStyle(fontSize: 13, color: AppTone.muted),
            ),
          )
        else
          ..._locations.map((loc) => _LocationRow(location: loc)),
        const SizedBox(height: 32),
      ],
    );
  }

  String _humanReason(String raw) {
    switch (raw) {
      case 'MISSED_PAYMENT':
        return 'Missed payment';
      case 'LATE_PAYMENT':
        return 'Late payment';
      case 'MANUAL_LOCK':
        return 'Manually locked by dealer';
      case 'FRAUD_ALERT':
        return 'Fraud alert triggered';
      default:
        return raw;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.loading,
    required this.onRefresh,
  });
  final String title;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted, fontWeight: FontWeight.w700),
          ),
        ),
        if (loading)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        else
          GestureDetector(
            onTap: onRefresh,
            child: const Icon(Icons.refresh_rounded, size: 16, color: AppTone.muted),
          ),
      ],
    );
  }
}

class _HistoryEventRow extends StatelessWidget {
  const _HistoryEventRow({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final type = text(event['event_type'], fallback: 'EVENT');
    final actor = text(event['actor_type'], fallback: '');
    final createdAt = text(event['created_at'], fallback: '');
    final color = _colorForType(type);
    final icon = _iconForType(type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _humanLabel(type),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTone.ink,
                  ),
                ),
                Row(
                  children: [
                    if (actor.isNotEmpty) ...[
                      Text(
                        actor,
                        style: const TextStyle(fontSize: 11, color: AppTone.muted),
                      ),
                      const Text(
                        ' · ',
                        style: TextStyle(fontSize: 11, color: AppTone.muted),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        _formatTimestamp(createdAt),
                        style: const TextStyle(fontSize: 11, color: AppTone.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForType(String type) {
    if (type.contains('FRAUD')) return AppTone.danger;
    if (type.contains('LOCK') || type == 'GRACE_EXPIRED') return AppTone.danger;
    if (type.contains('UNLOCK') || type == 'ENROLLED' || type == 'GRACE_GIVEN') {
      return AppTone.brand;
    }
    if (type.contains('SIM')) return AppTone.info;
    if (type.contains('CALL')) return Colors.orange;
    if (type.contains('SMS_HEARTBEAT')) return AppTone.brand;
    return AppTone.muted;
  }

  IconData _iconForType(String type) {
    if (type.contains('FRAUD')) return Icons.warning_amber_rounded;
    if (type == 'LOCKED' || type == 'GRACE_EXPIRED') return Icons.lock_outline;
    if (type == 'UNLOCKED' || type == 'GRACE_GIVEN') return Icons.lock_open_rounded;
    if (type == 'ENROLLED') return Icons.check_circle_outline;
    if (type.contains('SIM')) return Icons.sim_card_outlined;
    if (type.contains('CALL_DECLINED')) return Icons.call_end_outlined;
    if (type.contains('CALL_ANSWERED')) return Icons.call_outlined;
    if (type.contains('CALL_MISSED')) return Icons.phone_missed_outlined;
    if (type.contains('SMS_HEARTBEAT')) return Icons.message_outlined;
    if (type.contains('LOCATION')) return Icons.location_on_outlined;
    return Icons.circle_outlined;
  }

  String _humanLabel(String type) {
    const labels = {
      'LOCKED': 'Device locked',
      'UNLOCKED': 'Device unlocked',
      'ENROLLED': 'Device enrolled',
      'GRACE_GIVEN': 'Grace period granted',
      'GRACE_EXPIRED': 'Grace period expired',
      'FRAUD_SUSPECTED': 'Fraud suspected',
      'FRAUD_CONFIRMED': 'Fraud confirmed',
      'FRAUD_CLEARED': 'Fraud cleared',
      'SIM_CHANGED': 'SIM card changed',
      'SIM_UPDATED': 'Registered SIM updated',
      'SMS_HEARTBEAT_RECEIVED': 'SMS heartbeat received',
      'SMS_HEARTBEAT_MISSED': 'SMS heartbeat missed',
      'CALL_DECLINED': 'Dealer call declined',
      'CALL_ANSWERED': 'Dealer call answered',
      'CALL_MISSED': 'Dealer call missed',
      'BOOT_DETECTED': 'Device rebooted',
      'LOCATION_ANOMALY': 'Location anomaly detected',
      'DECOUPLED': 'Device decoupled',
    };
    return labels[type] ?? type.replaceAll('_', ' ').toLowerCase();
  }

  String _formatTimestamp(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location});
  final Map<String, dynamic> location;

  @override
  Widget build(BuildContext context) {
    final lat = location['latitude']?.toString() ?? '';
    final lng = location['longitude']?.toString() ?? '';
    final source = text(location['source'], fallback: 'gps');

    final latD = double.tryParse(lat);
    final lngD = double.tryParse(lng);
    final hasCoords = latD != null && lngD != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: hasCoords
            ? () {

              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTone.page,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTone.line),
          ),
          child: Row(
            children: [
              Icon(
                source == 'sms_heartbeat'
                    ? Icons.message_outlined
                    : Icons.location_on_outlined,
                size: 16,
                color: AppTone.brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCoords
                          ? '${latD.toStringAsFixed(5)}, ${lngD.toStringAsFixed(5)}'
                          : 'Unknown',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTone.ink,
                      ),
                    ),
                    Text(
                      '$source · $_formatTs',
                      style: const TextStyle(fontSize: 11, color: AppTone.muted),
                    ),
                  ],
                ),
              ),
              if (hasCoords)
                const Icon(Icons.open_in_new, size: 14, color: AppTone.muted),
            ],
          ),
        ),
      ),
    );
  }

  String get _formatTs {
    final raw = location['recorded_at']?.toString() ?? '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${local.day}/${local.month}/${local.year}';
  }
}
