import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pointycastle/export.dart' hide State, Padding;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/evidence_vault.dart';
import 'package:dealer_app/core/google_vault.dart';
import 'package:dealer_app/screens/shared/google_drive_onboarding_screen.dart';

String _normalizeImeiValue(String value) => value.replaceAll(RegExp(r'\D'), '');

bool _isValidImeiValue(String value) {
  final imei = _normalizeImeiValue(value);
  if (!RegExp(r'^\d{15}$').hasMatch(imei)) return false;

  var sum = 0;
  for (var i = 0; i < imei.length; i++) {
    var digit = int.parse(imei[i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 == 0;
}

List<String> _extractValidImeis(String rawValue) {
  final found = <String>{};
  final runs = RegExp(r'\d[\d\s\-]{13,40}\d')
      .allMatches(rawValue)
      .map((match) => _normalizeImeiValue(match.group(0) ?? ''));

  for (final run in runs) {
    if (run.length == 15 && _isValidImeiValue(run)) {
      found.add(run);
      continue;
    }
    if (run.length > 15) {
      for (var start = 0; start <= run.length - 15; start++) {
        final candidate = run.substring(start, start + 15);
        if (_isValidImeiValue(candidate)) found.add(candidate);
      }
    }
  }

  return found.take(2).toList();
}

class _ImeiVerification {
  const _ImeiVerification({
    required this.valid,
    required this.title,
    required this.message,
    required this.tone,
    required this.icon,
  });

  final bool valid;
  final String title;
  final String message;
  final Color tone;
  final IconData icon;
}

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
  bool _imeiVerifyBusy = false;
  _ImeiVerification? _imeiVerification;

  // Step 3 — EMI terms
  final _totalAmountController = TextEditingController();
  final _downPaymentController = TextEditingController();
  final _interestRateController = TextEditingController();
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
  String? _enrollmentId;
  String? _deviceId;
  String? _enrollmentToken;
  bool _enrollBusy = false;
  bool _emiSaving = false;
  bool _fallbackSaving = false;
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
    _imei1Controller.addListener(_clearImeiVerification);
    _imei2Controller.addListener(_clearImeiVerification);
    _brandController.addListener(_clearImeiVerification);
    _modelController.addListener(_clearImeiVerification);
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
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final imei1 = _normalizeImei(_imei1Controller.text);
    final hasAnyFallback =
        brand.isNotEmpty ||
        model.isNotEmpty ||
        imei1.isNotEmpty ||
        _normalizeImei(_imei2Controller.text).isNotEmpty;
    if (!hasAnyFallback) return null;
    if (brand.isEmpty) {
      return 'Enter phone brand or leave all fallback fields blank.';
    }
    if (model.isEmpty) {
      return 'Enter phone model or leave all fallback fields blank.';
    }
    if (imei1.isEmpty) {
      return 'Enter IMEI 1 or leave all fallback fields blank.';
    }
    if (!_isValidImei(imei1)) return 'IMEI 1 is not a valid IMEI number.';
    final imei2 = _normalizeImei(_imei2Controller.text);
    if (imei2.isNotEmpty && !_isValidImei(imei2)) {
      return 'IMEI 2 is not a valid IMEI number.';
    }
    if (imei2.isNotEmpty && imei1 == imei2) {
      return 'IMEI 1 and IMEI 2 cannot be the same.';
    }
    return null;
  }

  String? _validateStep3() {
    final phonePrice = _parseNumber(_totalAmountController.text);
    final down = _parseNumber(_downPaymentController.text);
    final interestRate = _parseNumber(_interestRateController.text);
    final duration = int.tryParse(_durationController.text.trim());
    final grace = int.tryParse(_graceDaysController.text.trim());

    final downVal = down ?? 0.0;
    final interestVal = interestRate ?? 0.0;

    if (phonePrice == null || phonePrice <= 0) {
      return 'Enter the total phone price.';
    }
    if (downVal < 0) return 'Down payment cannot be negative.';
    if (downVal >= phonePrice) {
      return 'Down payment must be less than the phone price.';
    }
    if (interestVal < 0 || interestVal > 100) {
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
    final down = _parseNumber(_downPaymentController.text) ?? 0.0;
    final interestRate = _parseNumber(_interestRateController.text) ?? 0.0;
    final duration = int.tryParse(_durationController.text.trim());
    if (phonePrice == null || phonePrice <= 0) return null;
    if (down < 0 || down >= phonePrice) return null;
    if (interestRate < 0 || interestRate > 100) return null;
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

  String _normalizeImei(String value) => _normalizeImeiValue(value);

  bool _isValidImei(String value) => _isValidImeiValue(value);

  void _clearImeiVerification() {
    if (_imeiVerification == null || _imeiVerifyBusy) return;
    setState(() => _imeiVerification = null);
  }

  Future<void> _verifyImeiDetails() async {
    if (_imeiVerifyBusy) return;
    FocusScope.of(context).unfocus();
    setState(() => _imeiVerifyBusy = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final imei1 = _normalizeImei(_imei1Controller.text);
      final imei2 = _normalizeImei(_imei2Controller.text);
      final brand = _brandController.text.trim();
      final model = _modelController.text.trim();

      _ImeiVerification result;
      if (imei1.isEmpty) {
        result = const _ImeiVerification(
          valid: false,
          title: 'IMEI missing',
          message: 'Enter or scan IMEI 1 before verification.',
          tone: AppTone.danger,
          icon: Icons.error_outline,
        );
      } else if (!_isValidImei(imei1)) {
        result = const _ImeiVerification(
          valid: false,
          title: 'IMEI 1 failed',
          message: 'The number does not pass the official IMEI checksum.',
          tone: AppTone.danger,
          icon: Icons.report_gmailerrorred_outlined,
        );
      } else if (imei2.isNotEmpty && !_isValidImei(imei2)) {
        result = const _ImeiVerification(
          valid: false,
          title: 'IMEI 2 failed',
          message: 'The second IMEI does not pass the official checksum.',
          tone: AppTone.danger,
          icon: Icons.report_gmailerrorred_outlined,
        );
      } else if (imei2.isNotEmpty && imei1 == imei2) {
        result = const _ImeiVerification(
          valid: false,
          title: 'Duplicate IMEI',
          message: 'IMEI 1 and IMEI 2 must be different for dual-SIM phones.',
          tone: AppTone.danger,
          icon: Icons.content_copy_outlined,
        );
      } else if (brand.isEmpty || model.isEmpty) {
        result = _ImeiVerification(
          valid: true,
          title: 'IMEI checksum passed',
          message:
              'TAC ${imei1.substring(0, 8)} is valid. Add brand and model, then verify against the box or *#06#.',
          tone: AppTone.warning,
          icon: Icons.fact_check_outlined,
        );
      } else {
        final dual = imei2.isEmpty
            ? 'Single IMEI captured.'
            : 'Dual IMEI captured.';
        result = _ImeiVerification(
          valid: true,
          title: 'Device details verified locally',
          message:
              '$brand $model passed IMEI checksum. TAC ${imei1.substring(0, 8)} recorded. $dual',
          tone: AppTone.brand,
          icon: Icons.verified_outlined,
        );
      }
      if (mounted) setState(() => _imeiVerification = result);
    } finally {
      if (mounted) setState(() => _imeiVerifyBusy = false);
    }
  }

  Future<void> _scanImeis() async {
    final scanned = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const _ImeiScannerScreen()),
    );
    if (!mounted || scanned == null) return;
    if (scanned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No valid IMEI found. Try the box QR/barcode or enter manually.',
          ),
          backgroundColor: AppTone.danger,
        ),
      );
      return;
    }
    setState(() {
      _imei1Controller.text = scanned.first;
      _imei2Controller.text = scanned.length > 1 ? scanned[1] : '';
      _imeiVerification = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          scanned.length > 1 ? 'IMEI 1 and IMEI 2 captured.' : 'IMEI captured.',
        ),
        backgroundColor: AppTone.brand,
      ),
    );
  }

  int get _totalSteps => widget.requireEvidence ? 8 : 7;
  int get _qrStep => 2;
  int get _codeStep => 3;
  int get _emiStep => 4;
  int get _evidenceStep => 5;
  int get _fallbackStep => widget.requireEvidence ? 6 : 5;
  int get _reviewStep => widget.requireEvidence ? 7 : 6;

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
    if (_enrollmentToken != null && _enrollmentId != null) return;
    setState(() {
      _enrollBusy = true;
      _error = null;
    });
    try {
      final nidHash = _sha256(_nidController.text.trim());
      final body = <String, dynamic>{
        'customer_name': _nameController.text.trim(),
        'nid_hash': nidHash,
        'phone_number': _phoneController.text.trim(),
        'tier': _selectedTier,
      };

      final res = await widget.api.post(
        '/api/v1/dealer/enrollments',
        data: body,
      );
      if (mounted) {
        final d = asMap(res.data);
        final deviceId = text(d['device_id'] ?? d['deviceId']);
        final token = text(d['token']).trim();
        if (!RegExp(r'^\d{6}$').hasMatch(token)) {
          throw Exception('Server did not return a valid activation code.');
        }
        setState(() {
          _enrollmentId = text(d['enrollment_id'] ?? d['enrollmentId']);
          _deviceId = deviceId;
          _enrollmentToken = token;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _enrollBusy = false);
    }
  }

  Future<void> _goToCodeStep() async {
    if (_enrollBusy) return;
    final validation = _validateStep1();
    if (validation != null) {
      _next(validation);
      return;
    }

    await _createEnrollment();
    if (!mounted) return;
    if (_enrollmentToken != null && _enrollmentToken!.isNotEmpty) {
      setState(() => _step = _codeStep);
    }
  }

  Future<void> _saveEmiTermsAndNext() async {
    final validation = _validateStep3();
    if (validation != null) {
      _next(validation);
      return;
    }
    if (_enrollmentId == null || _enrollmentId!.isEmpty) {
      await _createEnrollment();
    }
    if (_enrollmentId == null || _enrollmentId!.isEmpty) return;

    setState(() {
      _emiSaving = true;
      _error = null;
    });
    try {
      final emi = _calculateEmi();
      if (emi == null) throw Exception('Enter valid EMI terms.');
      final res = await widget.api.patch(
        '/api/v1/dealer/enrollments/$_enrollmentId/emi-terms',
        data: {
          'totalAmount': emi.totalPayable,
          'downPayment': emi.downPayment,
          'emiAmount': emi.monthlyEmi,
          'duration': emi.duration,
          'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
          'graceDays': int.parse(_graceDaysController.text.trim()),
        },
      );
      final data = asMap(res.data);
      final nextDeviceId = text(data['device_id'] ?? data['deviceId']);
      if (mounted) {
        setState(() {
          if (nextDeviceId.isNotEmpty) _deviceId = nextDeviceId;
          _step = widget.requireEvidence ? _evidenceStep : _fallbackStep;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _emiSaving = false);
    }
  }

  Future<void> _saveDeviceFallbackAndReview() async {
    final validation = _validateStep2();
    if (validation != null) {
      _next(validation);
      return;
    }
    if (_enrollmentId == null || _enrollmentId!.isEmpty) {
      setState(() => _step = _reviewStep);
      return;
    }

    final body = <String, dynamic>{};
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final imei1 = _normalizeImei(_imei1Controller.text);
    final imei2 = _normalizeImei(_imei2Controller.text);
    if (brand.isNotEmpty) body['brand'] = brand;
    if (model.isNotEmpty) body['model'] = model;
    if (imei1.isNotEmpty) body['imei1'] = imei1;
    if (imei2.isNotEmpty) body['imei2'] = imei2;
    if (body.isEmpty) {
      setState(() => _step = _reviewStep);
      return;
    }

    setState(() {
      _fallbackSaving = true;
      _error = null;
    });
    try {
      final res = await widget.api.patch(
        '/api/v1/dealer/enrollments/$_enrollmentId/device-fallback',
        data: body,
      );
      final data = asMap(res.data);
      final nextDeviceId = text(data['device_id'] ?? data['deviceId']);
      if (mounted) {
        setState(() {
          if (nextDeviceId.isNotEmpty) _deviceId = nextDeviceId;
          _step = _reviewStep;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = readableError(e));
    } finally {
      if (mounted) setState(() => _fallbackSaving = false);
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
    _downPaymentController.clear();
    _interestRateController.clear();
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
      _enrollmentId = null;
      _deviceId = null;
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
        return _buildStep5Qr();
      case 3:
        return _buildStep6Code();
      case 4:
        return _buildStep3EmiTerms();
      case 5:
        return widget.requireEvidence ? _buildStep4Evidence() : _buildStep2();
      case 6:
        return widget.requireEvidence ? _buildStep2() : _buildStep4Review();
      case 7:
        return _buildStep4Review();
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
          onPressed: () {
            final validation = _validateStep1();
            if (validation != null) {
              _next(validation);
              return;
            }
            setState(() => _step = _qrStep);
            _fetchQr();
            _createEnrollment();
          },
          child: const Text('Next - Enrollment QR'),
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
          step: _fallbackStep + 1,
          total: _totalSteps,
          title: 'Device fallback',
          subtitle:
              'Optional. Use this only if the user app could not read IMEI, brand, or model after owner setup.',
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
        _ScanImeiPanel(onScan: _scanImeis),
        const SizedBox(height: 12),
        _Field(
          controller: _imei1Controller,
          label: 'IMEI 1',
          hint: '15-digit IMEI',
          keyboard: TextInputType.number,
          maxLength: 15,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          suffixIcon: IconButton(
            tooltip: 'Scan IMEI',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scanImeis,
          ),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _imei2Controller,
          label: 'IMEI 2 (optional)',
          hint: '15-digit IMEI for dual-SIM',
          keyboard: TextInputType.number,
          maxLength: 15,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          suffixIcon: IconButton(
            tooltip: 'Scan IMEI',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: _scanImeis,
          ),
        ),
        const SizedBox(height: 8),
        _ImeiVerifyPanel(
          busy: _imeiVerifyBusy,
          result: _imeiVerification,
          onVerify: _verifyImeiDetails,
        ),
        const SizedBox(height: 8),
        InlineNotice(
          message:
              'Leave these fields blank when the user app captured the phone details automatically.',
          tone: AppTone.info,
          icon: Icons.phone_outlined,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _fallbackSaving ? null : _saveDeviceFallbackAndReview,
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
          step: _emiStep + 1,
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: calculation != null
                ? [
                    BoxShadow(
                      color: AppTone.brand.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: calculation == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTone.muted.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.calculate_outlined,
                            color: AppTone.muted,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Enter price, down payment, interest, and duration to calculate EMI.',
                            style: TextStyle(
                              color: AppTone.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppTone.brand, AppTone.brandDark],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.payments_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Payment summary',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_money(calculation.monthlyEmi)}/mo',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _EmiSummaryRow(
                                  'Finance amount',
                                  _money(calculation.financedAmount),
                                ),
                                _EmiSummaryRow(
                                  'Interest amount',
                                  _money(calculation.interestAmount),
                                ),
                                const Divider(height: 16, thickness: 1),
                                _EmiSummaryRow(
                                  'Monthly EMI',
                                  _money(calculation.monthlyEmi),
                                  bold: true,
                                  highlight: true,
                                ),
                                _EmiSummaryRow(
                                  'Total payable',
                                  _money(calculation.totalPayable),
                                  bold: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                      .animate()
                      .fadeIn(duration: 280.ms)
                      .slideY(begin: 0.04, end: 0, duration: 280.ms),
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
          onPressed: _emiSaving ? null : _saveEmiTermsAndNext,
          child: Text(
            _emiSaving
                ? 'Saving...'
                : widget.requireEvidence
                ? 'Next - Evidence vault'
                : 'Next - Device fallback',
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
          step: _evidenceStep + 1,
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
          onPressed: _enrollBusy
              ? null
              : () async {
                  final validation = _validateEvidenceStep();
                  if (validation != null) {
                    _next(validation);
                    return;
                  }
                  final deviceId = _deviceId;
                  if (deviceId == null || deviceId.isEmpty) {
                    setState(
                      () => _error =
                          'Create the activation code before registering evidence.',
                    );
                    return;
                  }
                  setState(() => _enrollBusy = true);
                  try {
                    await _registerEvidenceForDevice(
                      deviceId: deviceId,
                      nidHash: _sha256(_nidController.text.trim()),
                    );
                    if (mounted) setState(() => _step = _fallbackStep);
                  } catch (e) {
                    if (mounted) setState(() => _error = readableError(e));
                  } finally {
                    if (mounted) setState(() => _enrollBusy = false);
                  }
                },
          child: Text(_enrollBusy ? 'Saving...' : 'Next - Device fallback'),
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
          step: _reviewStep + 1,
          total: _totalSteps,
          title: 'Review enrollment',
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
          title: 'Device fallback',
          onEdit: () => setState(() => _step = _fallbackStep),
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
          onEdit: () => setState(() => _step = _emiStep),
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
              highlight: true,
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
            onEdit: () => setState(() => _step = _evidenceStep),
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
                  setState(() => _done = true);
                },
          child: const Text('Finish enrollment record'),
        ),
      ],
    );
  }

  // ── Step 4: QR provisioning (Device Owner — new factory-reset phones) ────

  Widget _buildStep5Qr() {
    final codeActionLabel = _enrollBusy
        ? 'Generating code...'
        : 'Next - Enter 6-digit code';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WizardHeader(
          step: _qrStep + 1,
          total: _totalSteps,
          title: 'Device Owner setup',
          subtitle:
              'For a brand new phone — scan this QR during Android setup.',
        ),
        const SizedBox(height: 16),
        _QrStepActions(
          busy: _enrollBusy,
          primaryLabel: codeActionLabel,
          onCode: _goToCodeStep,
          onSkip: _goToCodeStep,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          InlineNotice(
            message: _error!,
            tone: AppTone.danger,
            icon: Icons.error_outline,
          ),
        ],
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
          onPressed: _enrollBusy
              ? null
              : () async {
                  await _createEnrollment();
                  if (mounted && _enrollmentToken != null) {
                    setState(() => _step = _codeStep);
                  }
                },
          child: const Text('Next — Enter code on device'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _enrollBusy
              ? null
              : () async {
                  await _createEnrollment();
                  if (mounted && _enrollmentToken != null) {
                    setState(() => _step = _codeStep);
                  }
                },
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
          step: _codeStep + 1,
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
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: AppTone.brand.withValues(alpha: 0.25),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTone.brand.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.key_rounded,
                      color: AppTone.brand,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Activation code',
                      style: TextStyle(
                        color: AppTone.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ActivationCodeDisplay(token: _enrollmentToken!)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      duration: 400.ms,
                      curve: Curves.easeOutBack,
                    ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: AppTone.muted,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Valid for 10 minutes',
                          style: TextStyle(color: AppTone.muted, fontSize: 12),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: _enrollmentToken!),
                        );
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Code copied to clipboard'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTone.brand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy_rounded,
                              size: 12,
                              color: AppTone.brand,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Copy',
                              style: TextStyle(
                                color: AppTone.brand,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
            onPressed: () => setState(() => _step = _emiStep),
            child: const Text('Next - EMI details'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _enrollmentId = null;
                _deviceId = null;
                _enrollmentToken = null;
              });
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
    final customerName = _nameController.text.trim();
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final imei = _imei1Controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer pulse ring
              Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTone.brand.withValues(alpha: 0.06),
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.1, 1.1),
                    duration: 1800.ms,
                    curve: Curves.easeInOut,
                  ),
              // Mid ring
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTone.brand.withValues(alpha: 0.1),
                ),
              ).animate().scale(
                begin: const Offset(0, 0),
                end: const Offset(1, 1),
                duration: 500.ms,
                delay: 100.ms,
                curve: Curves.easeOutBack,
              ),
              // Inner filled circle + checkmark
              Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTone.brand, AppTone.brandDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x4000C896),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  )
                  .animate()
                  .scale(
                    begin: const Offset(0, 0),
                    end: const Offset(1, 1),
                    duration: 450.ms,
                    delay: 200.ms,
                    curve: Curves.easeOutBack,
                  )
                  .fadeIn(duration: 300.ms, delay: 200.ms),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
              'Device enrolled!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTone.ink,
              ),
            )
            .animate()
            .fadeIn(duration: 300.ms, delay: 400.ms)
            .slideY(begin: 0.1, end: 0, duration: 300.ms, delay: 400.ms),
        const SizedBox(height: 6),
        Text(
          '$customerName\'s device is now protected.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTone.muted, fontSize: 14),
        ).animate().fadeIn(duration: 300.ms, delay: 500.ms),
        const SizedBox(height: 28),
        // Device summary card
        Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _SuccessSummaryRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Customer',
                    value: customerName,
                  ),
                  if (brand.isNotEmpty || model.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SuccessSummaryRow(
                      icon: Icons.smartphone_rounded,
                      label: 'Device',
                      value: [
                        brand,
                        model,
                      ].where((s) => s.isNotEmpty).join(' '),
                    ),
                  ],
                  if (imei.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SuccessSummaryRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'IMEI',
                      value: imei,
                      mono: true,
                    ),
                  ],
                ],
              ),
            )
            .animate()
            .fadeIn(duration: 350.ms, delay: 550.ms)
            .slideY(begin: 0.08, end: 0, duration: 350.ms, delay: 550.ms),
        const SizedBox(height: 28),
        FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            )
            .animate()
            .fadeIn(duration: 300.ms, delay: 650.ms)
            .slideY(begin: 0.06, end: 0, duration: 300.ms, delay: 650.ms),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _bindAnother,
          child: const Text('Bind another device'),
        ).animate().fadeIn(duration: 300.ms, delay: 700.ms),
      ],
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────

class _QrStepActions extends StatelessWidget {
  const _QrStepActions({
    required this.busy,
    required this.primaryLabel,
    required this.onCode,
    required this.onSkip,
  });

  final bool busy;
  final String primaryLabel;
  final VoidCallback onCode;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onCode,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.pin_rounded),
          label: Text(primaryLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onSkip,
          icon: const Icon(Icons.skip_next_rounded),
          label: const Text('Skip QR - phone is already set up'),
        ),
      ],
    );
  }
}

class _ScanImeiPanel extends StatelessWidget {
  const _ScanImeiPanel({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTone.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: AppTone.brand,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan IMEI from box',
                  style: TextStyle(
                    color: AppTone.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Reads QR/barcode text and keeps only valid IMEI numbers.',
                  style: TextStyle(color: AppTone.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Scan'),
          ),
        ],
      ),
    );
  }
}

class _ImeiVerifyPanel extends StatelessWidget {
  const _ImeiVerifyPanel({
    required this.busy,
    required this.result,
    required this.onVerify,
  });

  final bool busy;
  final _ImeiVerification? result;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final current = result;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: current == null
            ? AppTone.page
            : current.tone.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current == null
              ? AppTone.line
              : current.tone.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (current?.tone ?? AppTone.info).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    current?.icon ?? Icons.manage_search_rounded,
                    color: current?.tone ?? AppTone.info,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.title ?? 'IMEI verification',
                  style: TextStyle(
                    color: current?.tone ?? AppTone.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  current?.message ??
                      'Checks the IMEI checksum and prepares the TAC for model lookup.',
                  style: const TextStyle(
                    color: AppTone.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : onVerify,
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text(busy ? 'Verifying' : "I'm verifying"),
          ),
        ],
      ),
    );
  }
}

class _ImeiScannerScreen extends StatefulWidget {
  const _ImeiScannerScreen();

  @override
  State<_ImeiScannerScreen> createState() => _ImeiScannerScreenState();
}

class _ImeiScannerScreenState extends State<_ImeiScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.pdf417,
    ],
  );
  bool _handled = false;
  String _status = 'Point camera at the IMEI QR/barcode on the box or sticker.';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_handled) return;
    final rawValues = capture.barcodes
        .map((barcode) => barcode.rawValue ?? barcode.displayValue ?? '')
        .where((value) => value.trim().isNotEmpty)
        .join('\n');
    if (rawValues.isEmpty) return;

    final imeis = _extractValidImeis(rawValues);
    if (imeis.isEmpty) {
      if (!mounted) return;
      setState(
        () => _status =
            'Barcode read, but no valid IMEI found. Try another code.',
      );
      return;
    }

    _handled = true;
    await _controller.stop();
    if (mounted) Navigator.pop(context, imeis);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan IMEI'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _handleCapture),
          Center(
            child: Container(
              width: 260,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTone.brand, AppTone.brandDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTone.brand.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                '$step',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            )
            .animate()
            .scale(
              begin: const Offset(0.7, 0.7),
              end: const Offset(1, 1),
              duration: 280.ms,
              curve: Curves.easeOutBack,
            )
            .fadeIn(duration: 200.ms),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Step $step of $total',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTone.muted,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                    title,
                    key: ValueKey(title),
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTone.ink,
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 220.ms)
                  .slideX(
                    begin: 0.04,
                    end: 0,
                    duration: 220.ms,
                    curve: Curves.easeOut,
                  ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: AppTone.muted, fontSize: 13),
              ).animate().fadeIn(duration: 260.ms, delay: 60.ms),
            ],
          ),
        ),
      ],
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard = TextInputType.text,
    this.maxLength,
    this.onEditingComplete,
    this.inputFormatters,
    this.suffixIcon,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboard;
  final int? maxLength;
  final VoidCallback? onEditingComplete;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppTone.brand.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: widget.keyboard,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        onEditingComplete: widget.onEditingComplete,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          counterText: '',
          suffixIcon: widget.suffixIcon,
          filled: true,
          fillColor: _focused
              ? const Color(0xFFF0FDF9)
              : const Color(0xFFF8F9FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTone.brand, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
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

  static IconData _iconFor(String title) {
    switch (title.toLowerCase()) {
      case 'customer':
        return Icons.person_outline_rounded;
      case 'device':
        return Icons.smartphone_rounded;
      case 'emi terms':
        return Icons.payments_outlined;
      case 'evidence vault':
        return Icons.lock_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: AppTone.brand),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTone.brand.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _iconFor(title),
                              color: AppTone.brand,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTone.ink,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onEdit,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTone.brand.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Edit',
                                style: TextStyle(
                                  color: AppTone.brand,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, thickness: 1),
                      const SizedBox(height: 8),
                      ...children,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTone.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                color: highlight ? AppTone.brand : AppTone.ink,
                fontSize: highlight ? 14 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Responsive 3+3 activation code display.
class _ActivationCodeDisplay extends StatelessWidget {
  const _ActivationCodeDisplay({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final digitsOnly = token.replaceAll(RegExp(r'\D'), '');
    final displayCode =
        (digitsOnly.length >= 6 ? digitsOnly.substring(0, 6) : digitsOnly)
            .padRight(6);
    final firstHalf = displayCode.substring(0, 3).split('');
    final secondHalf = displayCode.substring(3, 6).split('');

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 340.0;
        final compact = availableWidth < 300;
        final digitGap = compact ? 4.0 : 6.0;
        final separatorGap = compact ? 8.0 : 12.0;
        final dotSize = compact ? 5.0 : 6.0;
        final rawPillWidth =
            (availableWidth - (digitGap * 4) - (separatorGap * 2) - dotSize) /
            6;
        final pillWidth = rawPillWidth.clamp(26.0, 42.0);
        final pillHeight = (pillWidth * 1.24).clamp(38.0, 52.0);
        final fontSize = (pillWidth * 0.64).clamp(18.0, 28.0);

        Widget digitGroup(List<String> digits) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < digits.length; index++) ...[
                if (index > 0) SizedBox(width: digitGap),
                _CodeDigitPill(
                  digit: digits[index],
                  width: pillWidth,
                  height: pillHeight,
                  fontSize: fontSize,
                ),
              ],
            ],
          );
        }

        final codeRow = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            digitGroup(firstHalf),
            SizedBox(width: separatorGap),
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: AppTone.brand.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: separatorGap),
            digitGroup(secondHalf),
          ],
        );

        return Shimmer.fromColors(
          baseColor: AppTone.brand,
          highlightColor: AppTone.brandDark,
          period: const Duration(seconds: 3),
          child: FittedBox(fit: BoxFit.scaleDown, child: codeRow),
        );
      },
    );
  }
}

// Single digit pill for activation code display
class _CodeDigitPill extends StatelessWidget {
  const _CodeDigitPill({
    required this.digit,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  final String digit;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTone.brand.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTone.brand.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Text(
        digit,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: AppTone.brand,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// EMI summary row — used inside financial summary card
class _EmiSummaryRow extends StatelessWidget {
  const _EmiSummaryRow(
    this.label,
    this.value, {
    this.bold = false,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool bold;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: bold ? AppTone.ink : AppTone.muted,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: highlight ? AppTone.brand : AppTone.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// Success screen device summary row
class _SuccessSummaryRow extends StatelessWidget {
  const _SuccessSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTone.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTone.brand, size: 16),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTone.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTone.ink,
              fontSize: 13,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}
