import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:dealer_app/app/emi_locker_app.dart';

class BindDeviceWizard extends StatefulWidget {
  const BindDeviceWizard({super.key, required this.api});
  final ApiClient api;

  @override
  State<BindDeviceWizard> createState() => _BindDeviceWizardState();
}

class _BindDeviceWizardState extends State<BindDeviceWizard> {
  int _step = 1;

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

  // Step 4 — Token
  String? _enrollmentId;
  bool _enrollBusy = false;
  final _tokenController = TextEditingController();
  bool _verifyBusy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _nidController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _imei1Controller.dispose();
    _imei2Controller.dispose();
    _tokenController.dispose();
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
    if (_step == 1) {
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
      };
      final imei2 = _imei2Controller.text.trim();
      if (imei2.isNotEmpty) body['imei2'] = imei2;

      final res = await widget.api.post('/api/v1/dealer/enrollments', data: body);
      if (mounted) {
        setState(() => _enrollmentId = text(asMap(res.data)['enrollment_id']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _enrollBusy = false);
    }
  }

  Future<void> _verifyToken() async {
    final token = _tokenController.text.trim();
    if (token.length != 6) {
      setState(() => _error = 'Enter the 6-digit code shown on the customer\'s device.');
      return;
    }
    setState(() {
      _verifyBusy = true;
      _error = null;
    });
    try {
      await widget.api.post(
        '/api/v1/dealer/enrollments/$_enrollmentId/verify-token',
        data: {'token': token},
      );
      HapticFeedback.lightImpact();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _verifyBusy = false);
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
    _tokenController.clear();
    setState(() {
      _step = 1;
      _creditProfile = null;
      _enrollmentId = null;
      _error = null;
      _done = false;
    });
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
            _StepDots(current: _step, total: 4),
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
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      case 4: return _buildStep4();
      default: return const SizedBox.shrink();
    }
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
            _createEnrollment();
          },
          child: const Text('Confirm and send to device'),
        ),
      ],
    );
  }

  // ── Step 4: Token confirm ─────────────────────────────────────────────────

  Widget _buildStep4() {
    if (_done) return _buildSuccess();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 4,
          title: 'Confirm device',
          subtitle: 'A code has been sent to the customer\'s device.',
        ),
        const SizedBox(height: 20),
        if (_enrollBusy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          const Text(
            'Sending token to device…',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTone.muted),
          ),
        ] else if (_enrollmentId != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.06),
              border: Border.all(color: AppTone.brand.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(children: [
                  Icon(Icons.notifications_active_outlined, color: AppTone.brand, size: 18),
                  SizedBox(width: 8),
                  Text('Token sent', style: TextStyle(fontWeight: FontWeight.w700, color: AppTone.brand)),
                ]),
                SizedBox(height: 8),
                Text(
                  'Ask the customer to open the notification on their device. '
                  'A 6-digit code will appear briefly on screen.',
                  style: TextStyle(color: AppTone.ink, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Enter the code you see on their device:',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTone.ink),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tokenController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              color: AppTone.ink,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '_ _ _ _ _ _',
              hintStyle: TextStyle(
                color: AppTone.muted.withValues(alpha: 0.5),
                letterSpacing: 6,
                fontSize: 24,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTone.muted.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTone.brand, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            InlineNotice(message: _error!, tone: AppTone.danger, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _verifyBusy ? null : _verifyToken,
            child: _verifyBusy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirm'),
          ),
        ] else if (_error != null) ...[
          InlineNotice(message: _error!, tone: AppTone.danger, icon: Icons.error_outline),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _createEnrollment,
            child: const Text('Retry'),
          ),
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
