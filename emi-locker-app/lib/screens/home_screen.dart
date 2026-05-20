import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/fcm_service.dart';

class HomeScreen extends StatefulWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final VoidCallback onSignedOut;

  const HomeScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onSignedOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScheduleSummary? _schedule;
  bool _loading = true;
  String? _errorCode;

  AppStrings get _s => AppStrings.of(widget.language);

  @override
  void initState() {
    super.initState();
    _load();
    _registerFcm();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorCode = null;
    });

    final result = await DeviceService.instance.fetchSchedule();

    if (!mounted) return;

    if (result.isUnauthorized) {
      // Token refresh failed inside DeviceService — session fully expired
      await AuthService.instance.signOut();
      widget.onSignedOut();
      return;
    }

    setState(() {
      _schedule = result.data;
      _errorCode = result.isOk ? null : (result.errorCode ?? 'UNKNOWN');
      _loading = false;
    });
  }

  Future<void> _registerFcm() async {
    final token = AuthService.instance.appToken;
    if (token != null) {
      await FcmService.instance.registerTokenWithBackend(token);
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111128),
        title: Text(s.homeTitle, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => widget.onLanguageChanged(
              widget.language == AppLanguage.bangla ? AppLanguage.english : AppLanguage.bangla,
            ),
            child: Text(
              s.langToggleLabel,
              style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4FC3F7)),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF888888)),
            tooltip: s.homeSignOut,
            onPressed: _signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1565C0)))
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: _errorCode != null && _schedule == null
                    ? _buildError()
                    : _buildContent(),
              ),
            ),
    );
  }

  Widget _buildError() {
    final s = _s;
    return SizedBox(
      height: 400,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 48),
              const SizedBox(height: 16),
              Text(
                s.errorForCode(_errorCode ?? 'UNKNOWN'),
                style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final s = _s;
    final schedule = _schedule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFF1565C0), size: 28),
            const SizedBox(width: 10),
            Text(
              s.homeTitle,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (schedule == null)
          _buildCard(
            child: Text(
              s.homeNotAvailable,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          )
        else ...[
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(Icons.phone_android,
                    '${schedule.deviceBrand ?? ''} ${schedule.deviceModel ?? ''}'.trim()),
                if (schedule.lockLevel != null)
                  _row(Icons.lock, schedule.lockLevel!, color: const Color(0xFFFF6B6B)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('EMI Schedule'),
                const SizedBox(height: 8),
                _kv('Total', '৳${schedule.totalAmount.toStringAsFixed(0)}'),
                _kv('Monthly', '৳${schedule.emiAmount.toStringAsFixed(0)}'),
                _kv('Duration', '${schedule.duration} months'),
                _kv('Status', schedule.scheduleStatus),
                if (schedule.overdueCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B0A0A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${schedule.overdueCount} overdue installment${schedule.overdueCount > 1 ? 's' : ''}',
                        style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (schedule.installments.isNotEmpty) ...[
            _label('Installments'),
            const SizedBox(height: 8),
            ...schedule.installments.map(_buildInstallmentTile),
          ],
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildInstallmentTile(Map<String, dynamic> inst) {
    final number = inst['installment_number'] ?? inst['installmentNumber'] ?? '';
    final dueDate = inst['due_date'] ?? inst['dueDate'] ?? '';
    final amount = inst['amount'] ?? '';
    final paid = inst['payment_status'] == 'completed' || inst['paymentStatus'] == 'completed';
    final isPaid = paid || inst['payment_id'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPaid ? const Color(0xFF1B5E20) : const Color(0xFF2A2A4A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isPaid ? const Color(0xFF4CAF50) : const Color(0xFF888888),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '#$number  •  $dueDate',
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
            ),
          ),
          Text(
            '৳$amount',
            style: TextStyle(
              color: isPaid ? const Color(0xFF4CAF50) : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A4A)),
      ),
      child: child,
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 12, fontWeight: FontWeight.w600),
      );

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('$key: ', style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      );

  Widget _row(IconData icon, String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color ?? const Color(0xFF4FC3F7)),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
          ],
        ),
      );
}
