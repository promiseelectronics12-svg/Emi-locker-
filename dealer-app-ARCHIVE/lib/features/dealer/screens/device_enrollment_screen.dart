import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../shared/api/device_repository.dart';
import '../../../shared/api/key_repository.dart';
import '../../../shared/models/activation_key.dart';
import '../../../shared/models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';

class DeviceEnrollmentScreen extends StatefulWidget {
  const DeviceEnrollmentScreen({super.key});

  @override
  State<DeviceEnrollmentScreen> createState() => _DeviceEnrollmentScreenState();
}

class _DeviceEnrollmentScreenState extends State<DeviceEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerNidController = TextEditingController();
  final _emiAmountController = TextEditingController();
  final _totalInstallmentsController = TextEditingController();
  DateTime _customerDob = DateTime(1990, 1, 1);
  ActivationKey? _selectedKey;
  List<ActivationKey> _availableKeys = [];
  bool _isLoadingKeys = true;
  bool _isLoading = false;
  bool _nidVerified = false;
  String? _nidVerificationError;
  File? _nidPhoto;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAvailableKeys();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerNidController.dispose();
    _emiAmountController.dispose();
    _totalInstallmentsController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableKeys() async {
    try {
      final keyRepo = context.read<KeyRepository>();
      final keys = await keyRepo.getKeys(status: 'AVAILABLE');
      setState(() {
        _availableKeys = keys;
        _isLoadingKeys = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingKeys = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customerDob,
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
    );
    if (picked != null) {
      setState(() {
        _customerDob = picked;
      });
    }
  }

  Future<void> _verifyNid() async {
    if (_customerNidController.text.isEmpty ||
        _customerNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill name and NID first')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _nidVerified = false;
      _nidVerificationError = null;
    });

    try {
      final deviceRepo = context.read<DeviceRepository>();
      final result = await deviceRepo.verifyNid(
        nidNumber: _customerNidController.text,
        customerName: _customerNameController.text,
        dob: _customerDob,
      );

      setState(() {
        _nidVerified = result['verified'] as bool? ?? false;
        _nidVerificationError = result['error'] as String?;
        _isLoading = false;
      });

      if (_nidVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NID verified successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _nidVerified = false;
        _nidVerificationError = 'Verification failed';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickNidPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
      );

      if (image != null) {
        setState(() {
          _nidPhoto = File(image.path);
        });
      }
    }
  }

  Future<void> _scanQrCode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(),
      ),
    );
  }

  Future<void> _enrollDevice() async {
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an activation key')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Enrollment',
        content:
            'Enroll device for ${_customerNameController.text}?\n\nEMI: ${_emiAmountController.text} BDT x ${_totalInstallmentsController.text} installments',
        confirmText: 'Enroll',
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final deviceRepo = context.read<DeviceRepository>();
      await deviceRepo.enrollDevice(
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerNid: _customerNidController.text.trim(),
        customerDob: _customerDob,
        activationKey: _selectedKey!.keyCode,
        emiAmount: double.parse(_emiAmountController.text),
        totalInstallments: int.parse(_totalInstallmentsController.text),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device enrolled successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enrollment failed: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll New Device'),
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Activation Key',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (!_isLoadingKeys)
                              Text(
                                '${_availableKeys.length} available',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isLoadingKeys)
                          const Center(child: CircularProgressIndicator())
                        else if (_availableKeys.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'No activation keys available. Please purchase from reseller.',
                            ),
                          )
                        else
                          DropdownButtonFormField<ActivationKey>(
                            value: _selectedKey,
                            decoration: const InputDecoration(
                              hintText: 'Select activation key',
                            ),
                            items: _availableKeys.map((key) {
                              return DropdownMenuItem(
                                value: key,
                                child: Text(
                                  '...${key.keyCode.substring(key.keyCode.length - 8)}',
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedKey = value;
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'Please select an activation key';
                              }
                              return null;
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Customer Details',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _customerNameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Customer Name',
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter customer name';
                            }
                            if (value.length < 2) {
                              return 'Name is too short';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customerPhoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter phone number';
                            }
                            if (value.length < 11) {
                              return 'Invalid phone number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customerNidController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(17),
                          ],
                          decoration: InputDecoration(
                            labelText: 'NID Number',
                            prefixIcon: const Icon(Icons.badge),
                            suffixIcon: _nidPhoto == null
                                ? IconButton(
                                    icon: const Icon(Icons.camera_alt),
                                    onPressed: _pickNidPhoto,
                                  )
                                : const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.successColor,
                                  ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter NID number';
                            }
                            return null;
                          },
                        ),
                        if (_nidPhoto != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _nidPhoto!,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _selectDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Date of Birth',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(_customerDob),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _verifyNid,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _nidVerified
                                        ? Icons.check_circle
                                        : Icons.verified,
                                    color: _nidVerified
                                        ? AppTheme.successColor
                                        : null,
                                  ),
                            label: Text(
                              _nidVerified
                                  ? 'NID Verified'
                                  : 'Verify NID (Cost: 10 BDT)',
                            ),
                          ),
                        ),
                        if (_nidVerificationError != null && !_nidVerified) ...[
                          const SizedBox(height: 8),
                          Text(
                            _nidVerificationError!,
                            style: const TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMI Details',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emiAmountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'EMI Amount (BDT)',
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter EMI amount';
                            }
                            final amount = double.tryParse(value);
                            if (amount == null || amount <= 0) {
                              return 'Invalid amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _totalInstallmentsController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Total Installments',
                            prefixIcon: Icon(Icons.calendar_month),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter total installments';
                            }
                            final installments =
                                int.tryParse(value);
                            if (installments == null ||
                                installments <= 0 ||
                                installments > 48) {
                              return 'Invalid (1-48)';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Device QR (Optional)'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _enrollDevice,
                  child: const Text('Enroll Device'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      _hasScanned = true;
      Navigator.pop(context, barcode!.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Device QR'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primaryColor, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Text(
              'Position the QR code within the frame',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}