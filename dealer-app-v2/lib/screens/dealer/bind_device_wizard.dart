import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/evidence_vault.dart';
import 'package:dealer_app/core/google_vault.dart';
import 'package:dealer_app/screens/shared/google_drive_onboarding_screen.dart';

class BindDeviceWizard extends StatefulWidget {
  const BindDeviceWizard({
    super.key,
    required this.api,
    this.requireEvidence = true,
  });

  final ApiClient api;
  final bool requireEvidence;

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

  // Step 3 — EMI terms
  final _totalAmountController = TextEditingController();
  final _downPaymentController = TextEditingController(text: '0');
  final _interestRateController = TextEditingController(text: '0');
  final _emiAmountController = TextEditingController();
  final _durationController = TextEditingController(text: '12');
  final _graceDaysController = TextEditingController(text: '7');
  DateTime _startDate = DateTime.now();

  // Evidence vault
  final _imagePicker = ImagePicker();
  XFile? _nidFrontPhoto;
  XFile? _nidBackPhoto;
  XFile? _facePhoto;
  bool _vaultChecking = true;
  bool _vaultBound = false;
  String _vaultEmail = '';
  bool _evidenceRegistered = false;
  String? _evidenceHash;

  // QR provisioning (for new factory-reset phones)
  String? _qrValue;
  String? _qrError;
  bool _qrBusy = false;

  // Step 5 — Show 6-digit code
  String? _enrollmentToken;
  bool _enrollBusy = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _totalAmountController,
      _downPaymentController,
      _interestRateController,
      _durationController,
    ]) {
      controller.addListener(_onEmiInputChanged);
    }
    _loadInventory();
    if (widget.requireEvidence) {
      _loadVaultStatus();
    } else {
      _vaultChecking = false;
    }
  }

  void _onEmiInputChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInventory() async {
    try {
      final res = await widget.api.get('/api/v1/dealer/keys/inventory');
      final inv = asMap(res.data);
      if (!mounted) return;
      // Auto-select if only one tier has available keys
      final tiersWithKeys = ['standard', 'premium', 'vip']
          .where(
            (t) =>
                (int.tryParse(asMap(inv[t])['assigned']?.toString() ?? '0') ??
                    0) >
                0,
          )
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

  Future<void> _loadVaultStatus() async {
    final bound = await GoogleVault.isBound();
    final email = await GoogleVault.boundEmail() ?? '';
    if (!mounted) return;
    setState(() {
      _vaultBound = bound;
      _vaultEmail = email;
      _vaultChecking = false;
    });
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
    _totalAmountController.dispose();
    _downPaymentController.dispose();
    _interestRateController.dispose();
    _emiAmountController.dispose();
    _durationController.dispose();
    _graceDaysController.dispose();
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
    if (_phoneController.text.trim().isEmpty) {
      return 'Enter customer phone number.';
    }
    return null;
  }

  String? _validateStep2() {
    if (_brandController.text.trim().isEmpty) return 'Enter phone brand.';
    if (_modelController.text.trim().isEmpty) return 'Enter phone model.';
    final imei1 = _imei1Controller.text.trim();
    if (imei1.isEmpty) return 'Enter IMEI 1.';
    if (imei1.length != 15) return 'IMEI 1 must be exactly 15 digits.';
    final imei2 = _imei2Controller.text.trim();
    if (imei2.isNotEmpty && imei2.length != 15) {
      return 'IMEI 2 must be exactly 15 digits.';
    }
    return null;
  }

  String? _validateStep3() {
    final phonePrice = _parseNumber(_totalAmountController.text);
    final down = _parseNumber(_downPaymentController.text);
    final interestRate = _parseNumber(_interestRateController.text);
    final duration = int.tryParse(_durationController.text.trim());
    final grace = int.tryParse(_graceDaysController.text.trim());

    if (phonePrice == null || phonePrice <= 0) {
      return 'Enter the total phone price.';
    }
    if (down == null || down < 0) return 'Enter a valid down payment.';
    if (down >= phonePrice) {
      return 'Down payment must be less than the phone price.';
    }
    if (interestRate == null || interestRate < 0 || interestRate > 100) {
      return 'Interest rate must be 0-100%.';
    }
    if (duration == null || duration < 1 || duration > 60) {
      return 'Duration must be 1-60 months.';
    }
    if (grace == null || grace < 0 || grace > 30) {
      return 'Grace days must be 0-30.';
    }
    if (_calculateEmi() == null) return 'Enter valid EMI terms.';
    _syncCalculatedEmi();
    return null;
  }

  String? _validateEvidenceStep() {
    if (!widget.requireEvidence) return null;
    if (_vaultChecking) {
      return 'Checking Google Drive vault. Try again in a moment.';
    }
    if (!_vaultBound) return 'Connect the dealer Google Drive vault first.';
    if (_nidFrontPhoto == null) return 'Capture the NID front photo.';
    if (_nidBackPhoto == null) return 'Capture the NID back photo.';
    if (_facePhoto == null) return 'Capture the customer face photo.';
    return null;
  }

  double? _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', ''));
  }

  String _money(num value) {
    return NumberFormat('#,##0.00').format(value);
  }

  _EmiCalculation? _calculateEmi() {
    final phonePrice = _parseNumber(_totalAmountController.text);
    final down = _parseNumber(_downPaymentController.text);
    final interestRate = _parseNumber(_interestRateController.text);
    final duration = int.tryParse(_durationController.text.trim());
    if (phonePrice == null || phonePrice <= 0) return null;
    if (down == null || down < 0 || down >= phonePrice) return null;
    if (interestRate == null || interestRate < 0 || interestRate > 100) {
      return null;
    }
    if (duration == null || duration < 1 || duration > 60) return null;

    final financedAmount = phonePrice - down;
    final interestAmount = financedAmount * (interestRate / 100);
    final financedWithInterest = financedAmount + interestAmount;
    final monthlyEmi = double.parse(
      (financedWithInterest / duration).toStringAsFixed(2),
    );
    final totalPayable = double.parse(
      (down + (monthlyEmi * duration)).toStringAsFixed(2),
    );
    return _EmiCalculation(
      phonePrice: phonePrice,
      downPayment: down,
      interestRate: interestRate,
      financedAmount: financedAmount,
      interestAmount: interestAmount,
      monthlyEmi: monthlyEmi,
      duration: duration,
      totalPayable: totalPayable,
    );
  }

  void _syncCalculatedEmi() {
    final calculation = _calculateEmi();
    if (calculation == null) return;
    final nextValue = calculation.monthlyEmi.toStringAsFixed(2);
    if (_emiAmountController.text != nextValue) {
      _emiAmountController.text = nextValue;
    }
  }

  int get _totalSteps => widget.requireEvidence ? 8 : 7;
  int get _qrStep => widget.requireEvidence ? 6 : 5;
  int get _codeStep => widget.requireEvidence ? 7 : 6;

  Future<void> _openVaultSetup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoogleDriveOnboardingScreen()),
    );
    if (!mounted) return;
    setState(() => _vaultChecking = true);
    await _loadVaultStatus();
  }

  Future<void> _pickEvidencePhoto(_EvidenceSlot slot) async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: slot == _EvidenceSlot.face
            ? CameraDevice.front
            : CameraDevice.rear,
        imageQuality: 92,
        maxWidth: 1800,
      );
      if (photo == null || !mounted) return;
      setState(() {
        switch (slot) {
          case _EvidenceSlot.nidFront:
            _nidFrontPhoto = photo;
            break;
          case _EvidenceSlot.nidBack:
            _nidBackPhoto = photo;
            break;
          case _EvidenceSlot.face:
            _facePhoto = photo;
            break;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(readableError(e)),
          backgroundColor: AppTone.danger,
        ),
      );
    }
  }

  Future<void> _registerEvidenceForDevice({
    required String deviceId,
    required String nidHash,
  }) async {
    if (!widget.requireEvidence || _evidenceRegistered) return;
    if (_nidFrontPhoto == null || _nidBackPhoto == null || _facePhoto == null) {
      throw Exception('Evidence photos are required before creating the code.');
    }
    if (!await GoogleVault.isBound()) {
      throw Exception('Google Drive vault is not connected.');
    }

    final front = await _nidFrontPhoto!.readAsBytes();
    final back = await _nidBackPhoto!.readAsBytes();
    final face = await _facePhoto!.readAsBytes();
    final keyARef =
        'dealer_drive_${DateTime.now().millisecondsSinceEpoch}_${nidHash.substring(0, 12)}';
    final photoHash = await EvidenceVault.storeEvidence(
      nidHash: nidHash,
      deviceId: deviceId,
      nidFrontPhoto: Uint8List.fromList(front),
      nidBackPhoto: Uint8List.fromList(back),
      facePhoto: Uint8List.fromList(face),
      keyARef: keyARef,
      requireDriveBackup: true,
    );

    final vaultEmail = await GoogleVault.boundEmail() ?? _vaultEmail;
    final registerPayloads = [
      ('NID_FRONT', 'ev_${nidHash}_front.vault'),
      ('NID_BACK', 'ev_${nidHash}_back.vault'),
      ('FACE_PHOTO', 'ev_${nidHash}_face.vault'),
    ];
    for (final (type, fileName) in registerPayloads) {
      await widget.api.post(
        '/api/v1/evidence/register',
        data: {
          'nid_hash': nidHash,
          'device_id': deviceId,
          'evidence_type': type,
          'key_a_encrypted': keyARef,
          'photo_hash': photoHash,
          'dealer_seed_id': fileName,
          'reseller_seed_id': 'google_appdata:$vaultEmail',
        },
      );
    }
    _evidenceRegistered = true;
    _evidenceHash = photoHash;
  }

  void _next(String? validationError) {
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: AppTone.danger,
        ),
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
      final emi = _calculateEmi();
      if (emi == null) {
        throw Exception('Enter valid EMI terms before creating enrollment.');
      }
      final nidHash = _sha256(_nidController.text.trim());
      final body = <String, dynamic>{
        'customer_name': _nameController.text.trim(),
        'nid_hash': nidHash,
        'phone_number': _phoneController.text.trim(),
        'brand': _brandController.text.trim(),
        'model': _modelController.text.trim(),
        'imei1': _imei1Controller.text.trim(),
        'tier': _selectedTier,
        'totalAmount': emi.totalPayable,
        'downPayment': emi.downPayment,
        'emiAmount': emi.monthlyEmi,
        'duration': emi.duration,
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'graceDays': int.parse(_graceDaysController.text.trim()),
        'phonePrice': emi.phonePrice,
        'interestRate': emi.interestRate,
      };
      final imei2 = _imei2Controller.text.trim();
      if (imei2.isNotEmpty) body['imei2'] = imei2;

      final res = await widget.api.post(
        '/api/v1/dealer/enrollments',
        data: body,
      );
      if (mounted) {
        final d = asMap(res.data);
        final deviceId = text(d['device_id'] ?? d['deviceId']);
        if (widget.requireEvidence) {
          if (deviceId.isEmpty) {
            throw Exception(
              'Server did not return a device id for evidence registration.',
            );
          }
          await _registerEvidenceForDevice(
            deviceId: deviceId,
            nidHash: nidHash,
          );
        }
        setState(() {
          _enrollmentToken = text(d['token']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _enrollBusy = false);
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
    _totalAmountController.clear();
    _downPaymentController.text = '0';
    _interestRateController.text = '0';
    _emiAmountController.clear();
    _durationController.text = '12';
    _graceDaysController.text = '7';
    setState(() {
      _step = 0;
      _startDate = DateTime.now();
      _selectedTier = 'standard';
      _creditProfile = null;
      _qrValue = null;
      _qrError = null;
      _nidFrontPhoto = null;
      _nidBackPhoto = null;
      _facePhoto = null;
      _evidenceRegistered = false;
      _evidenceHash = null;
      _enrollmentToken = null;
      _error = null;
      _done = false;
    });
    _loadInventory();
  }

  Future<void> _fetchQr() async {
    setState(() {
      _qrBusy = true;
      _qrValue = null;
      _qrError = null;
    });
    try {
      final res = await widget.api.post('/api/v1/dealer/enrollment-qr');
      final d = asMap(res.data);
      if (mounted) setState(() => _qrValue = text(d['qr_value']));
    } catch (e) {
      if (mounted) {
        setState(() {
          _qrValue = '';
          _qrError = readableError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _qrBusy = false);
    }
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
            _StepDots(current: _step, total: _totalSteps),
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
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3EmiTerms();
      case 4:
        return widget.requireEvidence
            ? _buildStep4Evidence()
            : _buildStep4Review();
      case 5:
        return widget.requireEvidence ? _buildStep4Review() : _buildStep5Qr();
      case 6:
        return widget.requireEvidence ? _buildStep5Qr() : _buildStep6Code();
      case 7:
        return _buildStep6Code();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 0: Tier selection ─────────────────────────────────────────────────

  Widget _buildStep0() {
    if (_invLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    const tiers = ['standard', 'premium', 'vip'];
    const meta = {
      'standard': (
        'Standard',
        [Color(0xFF8E8E93), Color(0xFFAEAEB2)],
        Icons.vpn_key_outlined,
      ),
      'premium': (
        'Premium',
        [Color(0xFF0A84FF), Color(0xFF30B0C7)],
        Icons.stars_outlined,
      ),
      'vip': (
        'VIP',
        [Color(0xFFBF5AF2), Color(0xFFFFD60A)],
        Icons.workspace_premium_outlined,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 1,
          total: _totalSteps,
          title: 'Select key type',
          subtitle: 'Choose which key tier to use for this enrollment.',
        ),
        const SizedBox(height: 20),
        ...tiers.map((tier) {
          final (label, colors, icon) = meta[tier]!;
          final invT = asMap(_inventory[tier]);
          final available =
              int.tryParse(invT['assigned']?.toString() ?? '0') ?? 0;
          final quota = int.tryParse(invT['quota']?.toString() ?? '0') ?? 0;
          final hasKeys = available > 0;
          final selected = _selectedTier == tier;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: hasKeys
                  ? () => setState(() => _selectedTier = tier)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: hasKeys
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: colors,
                        )
                      : null,
                  color: hasKeys ? null : AppTone.page,
                  borderRadius: BorderRadius.circular(16),
                  border: selected
                      ? Border.all(color: AppTone.brand, width: 2.5)
                      : Border.all(color: AppTone.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: hasKeys ? Colors.white : AppTone.muted,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: hasKeys ? Colors.white : AppTone.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            hasKeys
                                ? '$available of $quota available'
                                : 'No keys available',
                            style: TextStyle(
                              color: hasKeys ? Colors.white70 : AppTone.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _selectedTier.isEmpty
              ? null
              : () => setState(() => _step = 1),
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
          step: 2,
          total: _totalSteps,
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
          step: 3,
          total: _totalSteps,
          title: 'Device information',
          subtitle:
              'Enter the phone details. Check the box or settings for IMEI.',
        ),
        const SizedBox(height: 20),
        _Field(
          controller: _brandController,
          label: 'Brand',
          hint: 'e.g. Samsung, Xiaomi',
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _modelController,
          label: 'Model',
          hint: 'e.g. Galaxy A15',
        ),
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
          child: const Text('Next — EMI terms'),
        ),
      ],
    );
  }

  // ── Step 3: Review ────────────────────────────────────────────────────────

  Widget _buildStep3EmiTerms() {
    final dateText = DateFormat('MMM d, yyyy').format(_startDate);
    final calculation = _calculateEmi();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 4,
          total: _totalSteps,
          title: 'EMI terms',
          subtitle: 'Capture the exact payment plan before binding the phone.',
        ),
        const SizedBox(height: 20),
        _Field(
          controller: _totalAmountController,
          label: 'Total phone price',
          hint: 'e.g. 36000',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _downPaymentController,
          label: 'Down payment',
          hint: 'e.g. 6000',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _interestRateController,
          label: 'Interest rate (%)',
          hint: 'e.g. 10',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _durationController,
          label: 'Duration months',
          hint: 'e.g. 3',
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _graceDaysController,
          label: 'Grace days',
          hint: 'e.g. 7',
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTone.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTone.line),
          ),
          child: calculation == null
              ? const Row(
                  children: [
                    Icon(Icons.calculate_outlined, color: AppTone.muted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Enter price, down payment, interest, and duration to calculate EMI.',
                        style: TextStyle(color: AppTone.muted, fontSize: 13),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.calculate_outlined, color: AppTone.brand),
                        SizedBox(width: 8),
                        Text(
                          'Calculated payment',
                          style: TextStyle(
                            color: AppTone.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReviewRow(
                      'Finance amount',
                      _money(calculation.financedAmount),
                    ),
                    _ReviewRow(
                      'Interest amount',
                      _money(calculation.interestAmount),
                    ),
                    _ReviewRow('Monthly EMI', _money(calculation.monthlyEmi)),
                    _ReviewRow(
                      'Total payable',
                      _money(calculation.totalPayable),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('First due date: $dateText'),
        ),
        const SizedBox(height: 8),
        InlineNotice(
          message:
              'Reminder and lock schedule will stop after this exact duration.',
          tone: AppTone.info,
          icon: Icons.event_available_outlined,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _next(_validateStep3()),
          child: Text(
            widget.requireEvidence ? 'Next - Evidence vault' : 'Next - Review',
          ),
        ),
      ],
    );
  }

  Widget _buildStep4Evidence() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: 5,
          total: _totalSteps,
          title: 'Evidence vault',
          subtitle:
              'Capture customer evidence and back it up encrypted to the dealer Google account.',
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _vaultBound ? AppTone.brandLight : AppTone.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _vaultBound
                  ? AppTone.brand.withValues(alpha: 0.35)
                  : AppTone.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _vaultBound
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                color: _vaultBound ? AppTone.brand : AppTone.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _vaultChecking
                      ? 'Checking Google Drive vault...'
                      : _vaultBound
                      ? 'Vault connected: $_vaultEmail'
                      : 'Connect Google Drive before continuing.',
                  style: const TextStyle(
                    color: AppTone.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: _vaultChecking ? null : _openVaultSetup,
                child: Text(_vaultBound ? 'Manage' : 'Connect'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _EvidenceCaptureTile(
          title: 'NID front',
          subtitle: 'Capture the front side clearly.',
          photo: _nidFrontPhoto,
          icon: Icons.badge_outlined,
          onPressed: () => _pickEvidencePhoto(_EvidenceSlot.nidFront),
        ),
        const SizedBox(height: 12),
        _EvidenceCaptureTile(
          title: 'NID back',
          subtitle: 'Capture the back side clearly.',
          photo: _nidBackPhoto,
          icon: Icons.chrome_reader_mode_outlined,
          onPressed: () => _pickEvidencePhoto(_EvidenceSlot.nidBack),
        ),
        const SizedBox(height: 12),
        _EvidenceCaptureTile(
          title: 'Customer photo',
          subtitle: 'Capture the customer face photo.',
          photo: _facePhoto,
          icon: Icons.face_retouching_natural_outlined,
          onPressed: () => _pickEvidencePhoto(_EvidenceSlot.face),
        ),
        const SizedBox(height: 12),
        InlineNotice(
          message:
              'Photos are encrypted on this phone and backed up in Google Drive app data. The backend stores only references and hashes.',
          tone: AppTone.info,
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _next(_validateEvidenceStep()),
          child: const Text('Next - Review'),
        ),
      ],
    );
  }

  Widget _buildStep4Review() {
    final tier = text(_creditProfile?['tier']);
    final imei2 = _imei2Controller.text.trim();
    final calculation = _calculateEmi();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: widget.requireEvidence ? 6 : 5,
          total: _totalSteps,
          title: 'Review before binding',
          subtitle:
              'Check everything carefully. Tap Edit to go back and fix a mistake.',
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
        const SizedBox(height: 12),
        _ReviewSection(
          title: 'EMI terms',
          onEdit: () => setState(() => _step = 3),
          children: [
            _ReviewRow(
              'Phone price',
              calculation == null
                  ? _totalAmountController.text.trim()
                  : _money(calculation.phonePrice),
            ),
            _ReviewRow(
              'Down payment',
              calculation == null
                  ? _downPaymentController.text.trim()
                  : _money(calculation.downPayment),
            ),
            _ReviewRow(
              'Interest rate',
              '${_interestRateController.text.trim()}%',
            ),
            if (calculation != null)
              _ReviewRow('Interest amount', _money(calculation.interestAmount)),
            if (calculation != null)
              _ReviewRow('Total payable', _money(calculation.totalPayable)),
            _ReviewRow(
              'Monthly EMI',
              calculation == null
                  ? _emiAmountController.text.trim()
                  : _money(calculation.monthlyEmi),
            ),
            _ReviewRow('Duration', '${_durationController.text.trim()} months'),
            _ReviewRow(
              'First due date',
              DateFormat('MMM d, yyyy').format(_startDate),
            ),
            _ReviewRow('Grace days', _graceDaysController.text.trim()),
          ],
        ),
        if (widget.requireEvidence) ...[
          const SizedBox(height: 12),
          _ReviewSection(
            title: 'Evidence vault',
            onEdit: () => setState(() => _step = 4),
            children: [
              _ReviewRow(
                'Google vault',
                _vaultEmail.isEmpty ? 'Connected' : _vaultEmail,
              ),
              _ReviewRow(
                'NID front',
                _nidFrontPhoto == null ? 'Missing' : 'Captured',
              ),
              _ReviewRow(
                'NID back',
                _nidBackPhoto == null ? 'Missing' : 'Captured',
              ),
              _ReviewRow(
                'Face photo',
                _facePhoto == null ? 'Missing' : 'Captured',
              ),
              if (_evidenceHash != null)
                _ReviewRow(
                  'Evidence hash',
                  '${_evidenceHash!.substring(0, 12)}...',
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _enrollBusy
              ? null
              : () {
                  setState(() => _step = _qrStep);
                  _fetchQr();
                  _createEnrollment();
                },
          child: const Text('Confirm and generate codes'),
        ),
      ],
    );
  }

  // ── Step 4: QR provisioning (Device Owner — new factory-reset phones) ────

  Widget _buildStep5Qr() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: widget.requireEvidence ? 7 : 6,
          total: _totalSteps,
          title: 'Device Owner setup',
          subtitle:
              'For a brand new phone — scan this QR during Android setup.',
        ),
        const SizedBox(height: 20),
        if (_qrBusy)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_qrValue != null && _qrValue!.isNotEmpty) ...[
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
                Text(
                  'For brand new phones:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTone.ink,
                    fontSize: 13,
                  ),
                ),
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
          InlineNotice(
            message: _qrError == null
                ? 'QR setup not available. Use the 6-digit code on the next screen instead.'
                : 'QR setup failed: $_qrError. Use the 6-digit code on the next screen or retry QR setup.',
            tone: AppTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _qrBusy ? null : _fetchQr,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry QR setup'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _step = _codeStep),
          child: const Text('Next — Enter code on device'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _step = _codeStep),
          child: const Text('Skip — phone is already set up'),
        ),
      ],
    );
  }

  // ── Step 5: Show 6-digit code to dealer ──────────────────────────────────

  Widget _buildStep6Code() {
    if (_done) return _buildSuccess();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: widget.requireEvidence ? 8 : 7,
          total: _totalSteps,
          title: 'Enter code on device',
          subtitle:
              'Type this code into the SIM Toolkit app on the customer\'s phone.',
        ),
        const SizedBox(height: 24),
        if (_enrollBusy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          const Text(
            'Generating code…',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTone.muted),
          ),
        ] else if (_enrollmentToken != null) ...[
          // Code display — large, easy to read at a glance
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.06),
              border: Border.all(
                color: AppTone.brand.withValues(alpha: 0.4),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Activation code',
                  style: TextStyle(
                    color: AppTone.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                Text(
                  'What to do now:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTone.ink,
                    fontSize: 13,
                  ),
                ),
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
            InlineNotice(
              message: _error!,
              tone: AppTone.danger,
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: () => setState(() => _done = true),
            child: const Text('Binding complete — Done'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              setState(() => _enrollmentToken = null);
              _createEnrollment();
            },
            child: const Text('Generate new code'),
          ),
        ] else if (_error != null) ...[
          InlineNotice(
            message: _error!,
            tone: AppTone.danger,
            icon: Icons.error_outline,
          ),
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
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTone.brand,
              size: 40,
            ),
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
            width: 20,
            height: 20,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: const BoxDecoration(
              color: AppTone.brand,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTone.ink, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmiCalculation {
  const _EmiCalculation({
    required this.phonePrice,
    required this.downPayment,
    required this.interestRate,
    required this.financedAmount,
    required this.interestAmount,
    required this.monthlyEmi,
    required this.duration,
    required this.totalPayable,
  });

  final double phonePrice;
  final double downPayment;
  final double interestRate;
  final double financedAmount;
  final double interestAmount;
  final double monthlyEmi;
  final int duration;
  final double totalPayable;
}

enum _EvidenceSlot { nidFront, nidBack, face }

class _EvidenceCaptureTile extends StatelessWidget {
  const _EvidenceCaptureTile({
    required this.title,
    required this.subtitle,
    required this.photo,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final XFile? photo;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final captured = photo != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: captured
              ? AppTone.brand.withValues(alpha: 0.45)
              : AppTone.line,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: captured
                  ? Image.file(File(photo!.path), fit: BoxFit.cover)
                  : ColoredBox(
                      color: AppTone.page,
                      child: Icon(icon, color: AppTone.muted),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTone.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  captured ? 'Captured' : subtitle,
                  style: TextStyle(
                    color: captured ? AppTone.brand : AppTone.muted,
                    fontSize: 12,
                    fontWeight: captured ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(
              captured ? Icons.refresh_rounded : Icons.photo_camera_outlined,
            ),
            label: Text(captured ? 'Retake' : 'Capture'),
          ),
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
          final active = i == current;
          final done = i < current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: (active || done)
                  ? AppTone.brand
                  : AppTone.muted.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.title,
    required this.subtitle,
    this.total = 7,
  });
  final int step;
  final String title;
  final String subtitle;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step $step of $total',
          style: const TextStyle(
            fontSize: 12,
            color: AppTone.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTone.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppTone.muted, fontSize: 13),
        ),
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
  const _ReviewSection({
    required this.title,
    required this.onEdit,
    required this.children,
  });
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
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTone.ink,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(color: AppTone.brand),
                ),
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTone.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTone.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
