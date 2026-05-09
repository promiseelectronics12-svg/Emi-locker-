import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

class BindDeviceWizard extends StatefulWidget {
  const BindDeviceWizard({super.key, required this.api});
  final ApiClient api;

  @override
  State<BindDeviceWizard> createState() => _BindDeviceWizardState();
}

class _BindDeviceWizardState extends State<BindDeviceWizard> {
  int _step = 0;

  // Step 0 — Tier selection
  String _selectedTier = 'standard';
  Map<String, dynamic> _inventory = {};
  bool _invLoading = true;

  // Step 1 — Customer
  final _nidController = TextEditingController();
  Map<String, dynamic>? _creditProfile;
  bool _creditLoading = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Step 2 — Device
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _imei1Controller = TextEditingController();
  final _imei2Controller = TextEditingController();

  // Step 4 — QR provisioning
  String? _qrValue;
  bool _qrBusy = false;

  // Step 5 — Show 6-digit code
  String? _enrollmentId;
  String? _enrollmentToken;   // plaintext code returned by server, shown to dealer
  bool _enrollBusy = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    try {
      final res = await widget.api.get('/api/v1/dealer/keys/inventory');
      final inv = asMap(res.data);
      if (!mounted) return;
      // Auto-select if only one tier has available keys
      final tiersWithKeys = ['standard', 'premium', 'vip']
          .where((t) => (int.tryParse(asMap(inv[t])['assigned']?.toString() ?? '0') ?? 0) > 0)
          .toList();
      setState(() {
        _inventory = inv;
        _invLoading = false;
        if (tiersWithKeys.length == 1) {
          _selectedTier = tiersWithKeys.first;
          _step = 1; // auto-skip tier selection
        } else if (tiersWithKeys.isNotEmpty) {
          _selectedTier = tiersWithKeys.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _invLoading = false);
    }
  }

  @override
  void dispose() {
    _nidController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _imei1Controller.dispose();
    _imei2Controller.dispose();
    super.dispose();
  }

  String _sha256(String input) {
    final digest = SHA256Digest();
    final bytes = utf8.encode(input);
    final hash = digest.process(Uint8List.fromList(bytes));
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _lookupCredit() async {
    final nid = _nidController.text.trim();
    if (nid.isEmpty) return;
    setState(() {
      _creditLoading = true;
      _creditProfile = null;
    });
    try {
      final res = await widget.api.post(
        '/api/v1/dealer/customer/lookup',
        data: {'nid_hash': _sha256(nid)},
      );
      if (mounted) setState(() => _creditProfile = asMap(res.data));
    } catch (_) {
      if (mounted) setState(() => _creditProfile = {});
    } finally {
      if (mounted) setState(() => _creditLoading = false);
    }
  }

  String? _validateStep1() {
    if (_nidController.text.trim().isEmpty) return 'Enter customer NID.';
    if (_nameController.text.trim().isEmpty) return 'Enter customer name.';
    if (_phoneController.text.trim().isEmpty) return 'Enter customer phone number.';
    return null;
  }

  String? _validateStep2() {
    if (_brandController.text.trim().isEmpty) return 'Enter phone brand.';
    if (_modelController.text.trim().isEmpty) return 'Enter phone model.';
    final imei1 = _imei1Controller.text.trim();
    if (imei1.isEmpty) return 'Enter IMEI 1.';
    if (imei1.length != 15) return 'IMEI 1 must be exactly 15 digits.';
    final imei2 = _imei2Controller.text.trim();
    if (imei2.isNotEmpty && imei2.length != 15) return 'IMEI 2 must be exactly 15 digits.';
    return null;
  }

  void _next(String? validationError) {
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError), backgroundColor: AppTone.danger),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _step++);
  }

  void _back() {
    if (_step <= 1) {
      Navigator.pop(context);
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _createEnrollment() async {
    setState(() {
      _enrollBusy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'customer_name': _nameController.text.trim(),
        'nid_hash': _sha256(_nidController.text.trim()),
        'phone_number': _phoneController.text.trim(),
        'brand': _brandController.text.trim(),
        'model': _modelController.text.trim(),
        'imei1': _imei1Controller.text.trim(),
        'tier': _selectedTier,
      };
      final imei2 = _imei2Controller.text.trim();
      if (imei2.isNotEmpty) body['imei2'] = imei2;

      final res = await widget.api.post('/api/v1/dealer/enrollments', data: body);
      if (mounted) {
        final d = asMap(res.data);
        setState(() {
          _enrollmentId    = text(d['enrollment_id']);
          _enrollmentToken = text(d['token']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _enrollBusy = false);
    }
  }

  Future<void> _fetchQr() async {
    setState(() { _qrBusy = true; _qrValue = null; });
    try {
      final res = await widget.api.post('/api/v1/dealer/enrollment-qr');
      final d = asMap(res.data);
      if (mounted) setState(() => _qrValue = text(d['qr_value']));
    } catch (_) {
      // QR unavailable — dealer can skip and use 6-digit code only
      if (mounted) setState(() => _qrValue = '');
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
  }

  void _bindAnother() {
    _nidController.clear();
    _nameController.clear();
    _phoneController.clear();
    _brandController.clear();
    _modelController.clear();
    _imei1Controller.clear();
    _imei2Controller.clear();
    setState(() {
      _step = 0;
      _selectedTier = 'standard';
      _creditProfile = null;
      _qrValue = null;
      _enrollmentId = null;
      _enrollmentToken = null;
      _error = null;
      _done = false;
    });
    _loadInventory();
  }

  String _maskNid(String nid) {
    if (nid.length <= 4) return nid;
    return '${'•' * (nid.length - 4)}${nid.substring(nid.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTone.surface,
      appBar: AppBar(
        backgroundColor: AppTone.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTone.ink),
          onPressed: _back,
        ),
        title: Text(
          'Bind New Device',
          style: const TextStyle(
            color: AppTone.ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepDots(current: _step, total: 6),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: _buildStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _buildStep0();
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      case 4: return _buildStep4Qr();
      case 5: return _buildStep5Code();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 0: Tier selection ─────────────────────────────────────────────────

  Widget _buildStep0() {
    if (_invLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ));
    }

    const tiers = ['standard', 'premium', 'vip'];
    const meta = {
      'standard': ('Standard', [Color(0xFF8E8E93), Color(0xFFAEAEB2)], Icons.vpn_key_outlined),
      'premium':  ('Premium',  [Color(0xFF0A84FF), Color(0xFF30B0C7)], Icons.stars_outlined),
      'vip':      ('VIP',      [Color(0xFFBF5AF2), Color(0xFFFFD60A)], Icons.workspace_premium_outlined),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 1,
          title: 'Select key type',
          subtitle: 'Choose which key tier to use for this enrollment.',
        ),
        const SizedBox(height: 20),
        ...tiers.map((tier) {
          final (label, colors, icon) = meta[tier]!;
          final invT = asMap(_inventory[tier]);
          final available = int.tryParse(invT['assigned']?.toString() ?? '0') ?? 0;
          final quota = int.tryParse(invT['quota']?.toString() ?? '0') ?? 0;
          final hasKeys = available > 0;
          final selected = _selectedTier == tier;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: hasKeys ? () => setState(() => _selectedTier = tier) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: hasKeys
                      ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)
                      : null,
                  color: hasKeys ? null : AppTone.page,
                  borderRadius: BorderRadius.circular(16),
                  border: selected ? Border.all(color: AppTone.brand, width: 2.5) : Border.all(color: AppTone.line),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: hasKeys ? Colors.white : AppTone.muted, size: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                            style: TextStyle(
                              color: hasKeys ? Colors.white : AppTone.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            )),
                          Text(hasKeys ? '$available of $quota available' : 'No keys available',
                            style: TextStyle(
                              color: hasKeys ? Colors.white70 : AppTone.muted,
                              fontSize: 12,
                            )),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: Colors.white, size: 22),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _selectedTier.isEmpty ? null : () => setState(() => _step = 1),
          child: const Text('Continue'),
        ),
      ],
    );
  }

  // ── Step 1: Customer ──────────────────────────────────────────────────────

  Widget _buildStep1() {
    final tier = text(_creditProfile?['tier']);
    final paymentRate = _creditProfile?['payment_rate'];
    final devicesCompleted = _creditProfile?['devices_completed'];
    final noRecord = _creditProfile != null && tier.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 1,
          title: 'Customer information',
          subtitle: 'Enter the NID to check credit history first.',
        ),
        const SizedBox(height: 20),
        _Field(
          controller: _nidController,
          label: 'Customer NID',
          hint: 'National ID number',
          keyboard: TextInputType.number,
          onEditingComplete: _lookupCredit,
        ),
        const SizedBox(height: 8),
        if (_creditLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SkeletonBox(width: double.infinity, height: 44),
          )
        else if (_creditProfile != null) ...[
          if (noRecord)
            const InlineNotice(
              message: 'No credit history — first-time customer.',
              tone: AppTone.warning,
              icon: Icons.info_outline,
            )
          else if (tier == 'BLACKLISTED' || tier == 'RED')
            InlineNotice(
              message: 'High risk customer ($tier) — proceed with caution.',
              tone: AppTone.danger,
              icon: Icons.warning_amber_rounded,
            )
          else
            InlineNotice(
              message: tier == 'GOLD'
                  ? 'Excellent credit. ${paymentRate != null ? 'Payment rate: $paymentRate%.' : ''} ${devicesCompleted != null ? '$devicesCompleted devices completed.' : ''}'
                  : 'Credit tier: $tier. ${paymentRate != null ? 'Payment rate: $paymentRate%.' : ''}',
              tone: AppTone.brand,
              icon: Icons.verified_outlined,
            ),
          const SizedBox(height: 8),
        ],
        _Field(
          controller: _nameController,
          label: 'Customer full name',
          hint: 'As on NID',
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _phoneController,
          label: 'Customer phone number',
          hint: '+8801XXXXXXXXX',
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _next(_validateStep1()),
          child: const Text('Next — Device info'),
        ),
      ],
    );
  }

  // ── Step 2: Device ────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 2,
          title: 'Device information',
          subtitle: 'Enter the phone details. Check the box or settings for IMEI.',
        ),
        const SizedBox(height: 20),
        _Field(controller: _brandController, label: 'Brand', hint: 'e.g. Samsung, Xiaomi'),
        const SizedBox(height: 12),
        _Field(controller: _modelController, label: 'Model', hint: 'e.g. Galaxy A15'),
        const SizedBox(height: 12),
        _Field(
          controller: _imei1Controller,
          label: 'IMEI 1',
          hint: '15-digit IMEI',
          keyboard: TextInputType.number,
          maxLength: 15,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _imei2Controller,
          label: 'IMEI 2 (optional)',
          hint: '15-digit IMEI for dual-SIM',
          keyboard: TextInputType.number,
          maxLength: 15,
        ),
        const SizedBox(height: 8),
        InlineNotice(
          message: 'Dial *#06# on the device to confirm IMEI numbers.',
          tone: AppTone.info,
          icon: Icons.phone_outlined,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _next(_validateStep2()),
          child: const Text('Next — Review'),
        ),
      ],
    );
  }

  // ── Step 3: Review ────────────────────────────────────────────────────────

  Widget _buildStep3() {
    final tier = text(_creditProfile?['tier']);
    final imei2 = _imei2Controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 3,
          title: 'Review before binding',
          subtitle: 'Check everything carefully. Tap Edit to go back and fix a mistake.',
        ),
        const SizedBox(height: 20),
        _ReviewSection(
          title: 'Customer',
          onEdit: () => setState(() => _step = 1),
          children: [
            _ReviewRow('NID', _maskNid(_nidController.text.trim())),
            if (tier.isNotEmpty) _ReviewRow('Credit tier', tier),
            _ReviewRow('Name', _nameController.text.trim()),
            _ReviewRow('Phone', _phoneController.text.trim()),
          ],
        ),
        const SizedBox(height: 12),
        _ReviewSection(
          title: 'Device',
          onEdit: () => setState(() => _step = 2),
          children: [
            _ReviewRow('Brand', _brandController.text.trim()),
            _ReviewRow('Model', _modelController.text.trim()),
            _ReviewRow('IMEI 1', _imei1Controller.text.trim()),
            _ReviewRow('IMEI 2', imei2.isEmpty ? '—' : imei2),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() => _step = 4);
            // Fire both in parallel — QR for Device Owner setup, token for 6-digit binding
            _fetchQr();
            _createEnrollment();
          },
          child: const Text('Confirm and generate codes'),
        ),
      ],
    );
  }

  // ── Step 4: QR provisioning ───────────────────────────────────────────────

  Widget _buildStep4Qr() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 4,
          title: 'Device Owner setup',
          subtitle: 'For a brand new phone — scan this QR during Android setup.',
        ),
        const SizedBox(height: 20),
        if (_qrBusy)
          const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ))
        else if (_qrValue != null && _qrValue!.isNotEmpty) ...[
          // QR code
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTone.line),
              ),
              child: QrImageView(
                data: _qrValue!,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTone.page,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('For brand new phones:',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.ink, fontSize: 13)),
                SizedBox(height: 8),
                _Step('1', 'Power on the new phone'),
                _Step('2', 'On the Welcome screen — tap 6 times quickly'),
                _Step('3', 'Camera appears — scan this QR code'),
                _Step('4', 'Phone sets up automatically with Device Owner'),
                _Step('5', 'SIM Toolkit installs by itself'),
              ],
            ),
          ),
        ] else ...[
          // QR not available — graceful fallback
          InlineNotice(
            message: 'QR setup not available. Use the 6-digit code on the next screen instead.',
            tone: AppTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _step = 5),
          child: const Text('Next — Enter code on device'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = 5),
          child: const Text('Skip — phone is already set up'),
        ),
      ],
    );
  }

  // ── Step 5: Show 6-digit code to dealer ──────────────────────────────────

  Widget _buildStep5Code() {
    if (_done) return _buildSuccess();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 5,
          title: 'Enter code on device',
          subtitle: 'Type this code into the SIM Toolkit app on the customer\'s phone.',
        ),
        const SizedBox(height: 24),
        if (_enrollBusy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          const Text('Generating code…', textAlign: TextAlign.center,
              style: TextStyle(color: AppTone.muted)),
        ] else if (_enrollmentToken != null) ...[
          // Code display — large, easy to read at a glance
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.06),
              border: Border.all(color: AppTone.brand.withValues(alpha: 0.4), width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('Activation code',
                    style: TextStyle(color: AppTone.muted, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Text(
                  // Format as "847 291" — easier to read in two groups
                  '${_enrollmentToken!.substring(0, 3)}  ${_enrollmentToken!.substring(3)}',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: AppTone.brand,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Valid for 10 minutes',
                  style: TextStyle(color: AppTone.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTone.page,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What to do now:',
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.ink, fontSize: 13)),
                SizedBox(height: 8),
                _Step('1', 'Pick up the customer\'s phone'),
                _Step('2', 'Open the SIM Toolkit app'),
                _Step('3', 'Tap "Enter activation code"'),
                _Step('4', 'Type the code above'),
                _Step('5', 'The app will confirm binding automatically'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            InlineNotice(message: _error!, tone: AppTone.danger, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: () => setState(() => _done = true),
            child: const Text('Binding complete — Done'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () { setState(() { _enrollmentId = null; _enrollmentToken = null; }); _createEnrollment(); },
            child: const Text('Generate new code'),
          ),
        ] else if (_error != null) ...[
          InlineNotice(message: _error!, tone: AppTone.danger, icon: Icons.error_outline),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _createEnrollment, child: const Text('Retry')),
        ],
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppTone.brand, size: 40),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Device bound successfully',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTone.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_nameController.text.trim()}\'s device is now enrolled and protected.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTone.muted),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _bindAnother,
          child: const Text('Bind another device'),
        ),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: const BoxDecoration(color: AppTone.brand, shape: BoxShape.circle),
            child: Text(number,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(text, style: const TextStyle(color: AppTone.ink, fontSize: 13))),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) {
          final active = i + 1 == current;
          final done = i + 1 < current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: (active || done) ? AppTone.brand : AppTone.muted.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({required this.step, required this.title, required this.subtitle});
  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of 4',
          style: const TextStyle(fontSize: 12, color: AppTone.muted, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTone.ink),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppTone.muted, fontSize: 13)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard = TextInputType.text,
    this.maxLength,
    this.onEditingComplete,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboard;
  final int? maxLength;
  final VoidCallback? onEditingComplete;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLength: maxLength,
      onEditingComplete: onEditingComplete,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTone.brand, width: 2),
        ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.onEdit, required this.children});
  final String title;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTone.muted.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTone.ink)),
              const Spacer(),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Edit', style: TextStyle(color: AppTone.brand)),
              ),
            ],
          ),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppTone.muted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppTone.ink)),
          ),
        ],
      ),
    );
  }
}
