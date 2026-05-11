import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/widgets/grace_period_selector.dart';
import 'package:dealer_app/widgets/unlock_method_card.dart';

class UnlockFlowScreen extends StatefulWidget {
  const UnlockFlowScreen({
    super.key,
    required this.api,
    required this.deviceId,
    required this.deviceName,
  });

  final ApiClient api;
  final String deviceId;
  final String deviceName;

  @override
  State<UnlockFlowScreen> createState() => _UnlockFlowScreenState();
}

class _UnlockFlowScreenState extends State<UnlockFlowScreen> {
  // States: loading | ready | submitting | success | error
  String _state = 'loading';
  String _errorMsg = '';

  Map<String, dynamic>? _lockDetail;
  UnlockMethod _method = UnlockMethod.online;
  int _graceHours = 8;

  Map<String, dynamic>? _otpResult;

  @override
  void initState() {
    super.initState();
    _loadLockDetail();
  }

  Future<void> _loadLockDetail() async {
    setState(() => _state = 'loading');
    try {
      final res = await widget.api.get('/api/v1/dealer/devices/${widget.deviceId}/lock-detail');
      setState(() {
        _lockDetail = asMap(res.data);
        _state = 'ready';
      });
    } catch (e) {
      setState(() {
        _errorMsg = readableError(e);
        _state = 'error';
      });
    }
  }

  Future<void> _confirmUnlock() async {
    HapticFeedback.lightImpact();
    setState(() => _state = 'submitting');
    try {
      final res = await widget.api.post(
        '/api/v1/dealer/devices/${widget.deviceId}/unlock',
        data: {
          'method': _method == UnlockMethod.online ? 'online' : 'offline',
          'grace_hours': _graceHours,
        },
      );
      setState(() {
        _otpResult = _method == UnlockMethod.offline ? asMap(res.data) : null;
        _state = 'success';
      });
    } catch (e) {
      setState(() {
        _errorMsg = readableError(e);
        _state = 'error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Unlock · ${widget.deviceName}',
            overflow: TextOverflow.ellipsis),
      ),
      body: _buildBody(),
      bottomNavigationBar: _state == 'ready'
          ? _ActionBar(onConfirm: _confirmUnlock)
          : null,
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case 'loading':
        return const _LoadingSkeleton();
      case 'error':
        return _ErrorState(message: _errorMsg, onRetry: _loadLockDetail);
      case 'submitting':
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Sending unlock command…'),
            ],
          ),
        );
      case 'success':
        return _SuccessState(
          method: _method,
          graceHours: _graceHours,
          otpResult: _otpResult,
          onDone: () => Navigator.pop(context),
        );
      default:
        return _ReadyState(
          lockDetail: _lockDetail!,
          method: _method,
          graceHours: _graceHours,
          onMethodChanged: (m) => setState(() => _method = m),
          onGraceChanged: (h) => setState(() => _graceHours = h),
        );
    }
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({
    required this.lockDetail,
    required this.method,
    required this.graceHours,
    required this.onMethodChanged,
    required this.onGraceChanged,
  });

  final Map<String, dynamic> lockDetail;
  final UnlockMethod method;
  final int graceHours;
  final ValueChanged<UnlockMethod> onMethodChanged;
  final ValueChanged<int> onGraceChanged;

  @override
  Widget build(BuildContext context) {
    final lock = asMap(lockDetail['lock']);
    final emi = asMap(lockDetail['emi']);
    final lockLevel = text(lock['lock_level'], fallback: 'NONE');
    final reason    = text(lock['reason'], fallback: 'No reason provided');
    final lockedAt  = text(lock['locked_at']);
    final overdue   = lock['days_overdue'] ?? emi['days_overdue'];
    final isLocked  = lock['is_locked'] == true;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Lock status panel
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppTone.danger, width: 4)),
            color: AppTone.danger.withOpacity(0.04),
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
                  Text(isLocked ? 'Device locked' : 'No active lock',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppTone.danger)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTone.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Level $lockLevel',
                        style: const TextStyle(
                            fontSize: 11, color: AppTone.danger,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(reason, style: const TextStyle(fontSize: 13, color: AppTone.ink)),
              if (lockedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Locked $lockedAt',
                    style: const TextStyle(fontSize: 11, color: AppTone.muted)),
              ],
              if (overdue != null) ...[
                const SizedBox(height: 4),
                Text('$overdue days overdue',
                    style: const TextStyle(
                        fontSize: 11, color: AppTone.warning,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('Unlock method',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 10),
        UnlockMethodCard(
          method: UnlockMethod.online,
          selected: method == UnlockMethod.online,
          onTap: () => onMethodChanged(UnlockMethod.online),
        ),
        const SizedBox(height: 8),
        UnlockMethodCard(
          method: UnlockMethod.offline,
          selected: method == UnlockMethod.offline,
          onTap: () => onMethodChanged(UnlockMethod.offline),
        ),

        const SizedBox(height: 20),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (method == UnlockMethod.offline) ...[
                const InlineNotice(
                  message:
                      'You send an OTP SMS from your own phone. Customer enters it on the locked screen.',
                  tone: AppTone.info,
                  icon: Icons.sms_outlined,
                ),
                const SizedBox(height: 16),
              ],
              GracePeriodSelector(
                  selected: graceHours, onChanged: onGraceChanged),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({
    required this.method,
    required this.graceHours,
    required this.otpResult,
    required this.onDone,
  });

  final UnlockMethod method;
  final int graceHours;
  final Map<String, dynamic>? otpResult;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    if (method == UnlockMethod.online) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTone.brand.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppTone.brand, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Unlock command sent',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700,
                      color: AppTone.ink)),
              const SizedBox(height: 8),
              Text('Device will unlock within 60 seconds. Grace: ${graceHours}h.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTone.muted)),
              const SizedBox(height: 28),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ),
      );
    }

    // Offline OTP result
    final otp   = text(otpResult?['otp'], fallback: '——');
    final phone = text(otpResult?['customer_phone'], fallback: '');
    final smsText = text(otpResult?['sms_text'],
        fallback: 'Your unlock code: $otp');
    final expiresAt = text(otpResult?['expires_at']);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InlineNotice(
          message: 'SMS this code from your own phone to the customer.',
          tone: AppTone.brand,
          icon: Icons.check_circle_outline_rounded,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTone.brand.withOpacity(0.06),
            border: Border.all(color: AppTone.brand.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(otp,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: AppTone.ink,
                    letterSpacing: 8,
                  )),
              if (expiresAt.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Expires $expiresAt',
                    style: const TextStyle(
                        fontSize: 11, color: AppTone.muted)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('Copy'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: otp));
                        snack(context, 'OTP copied');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: const Text('Share SMS'),
                      onPressed: () => Share.share(smsText),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Customer phone: $phone',
              style: const TextStyle(fontSize: 13, color: AppTone.muted)),
        ],
        const SizedBox(height: 24),
        OutlinedButton(onPressed: onDone, child: const Text('Close')),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: FilledButton.icon(
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Confirm unlock'),
          onPressed: onConfirm,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ),
    );
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: double.infinity, height: 90),
          SizedBox(height: 20),
          SkeletonBox(width: 120, height: 14),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 72),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 72),
          SizedBox(height: 20),
          SkeletonBox(width: double.infinity, height: 80),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineNotice(
                message: message,
                tone: AppTone.danger,
                icon: Icons.error_outline_rounded),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
