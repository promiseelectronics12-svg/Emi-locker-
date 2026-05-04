import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/constants/constants.dart';
import '../bloc/dealer_bloc.dart';

class EnrollDeviceScreen extends StatefulWidget {
  const EnrollDeviceScreen({super.key});

  @override
  State<EnrollDeviceScreen> createState() => _EnrollDeviceScreenState();
}

class _EnrollDeviceScreenState extends State<EnrollDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerNIDController = TextEditingController();
  final _customerDOBController = TextEditingController();
  final _totalAmountController = TextEditingController();
  final _tenureController = TextEditingController();

  DateTime? _selectedDOB;
  String? _selectedKeyId;
  bool _nidVerified = false;
  bool _isGeneratingQR = false;
  String? _generatedQRData;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerNIDController.dispose();
    _customerDOBController.dispose();
    _totalAmountController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  Future<void> _verifyNID() async {
    if (_customerNIDController.text.isEmpty || _customerDOBController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter NID and Date of Birth'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    context.read<DealerBloc>().add(
          VerifyNID(
            nid: _customerNIDController.text.trim(),
            dob: _customerDOBController.text.trim(),
          ),
        );
  }

  Future<void> _generateQRCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isGeneratingQR = true);

    try {
      final monthlyInstallment = double.parse(_totalAmountController.text) /
          int.parse(_tenureController.text);

      final qrData = {
        'dealerId': await _getDealerId(),
        'customerName': _customerNameController.text.trim(),
        'customerPhone': _customerPhoneController.text.trim(),
        'customerNID': _customerNIDController.text.trim(),
        'totalAmount': double.parse(_totalAmountController.text),
        'tenure': int.parse(_tenureController.text),
        'monthlyInstallment': monthlyInstallment,
        'keyId': _selectedKeyId,
      };

      setState(() {
        _generatedQRData = qrData.toString();
        _isGeneratingQR = false;
      });
    } catch (e) {
      setState(() => _isGeneratingQR = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<String?> _getDealerId() async {
    final storage = await ApiClient().getAccessToken();
    return storage;
  }

  void _submitEnrollment() {
    if (_generatedQRData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please generate QR code first'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    context.read<DealerBloc>().add(
          EnrollDevice(
            data: {
              'customerName': _customerNameController.text.trim(),
              'customerPhone': _customerPhoneController.text.trim(),
              'customerNID': _customerNIDController.text.trim(),
              'customerDOB': _customerDOBController.text.trim(),
              'totalAmount': double.parse(_totalAmountController.text),
              'tenure': int.parse(_tenureController.text),
              'monthlyInstallment':
                  double.parse(_totalAmountController.text) / int.parse(_tenureController.text),
              'keyId': _selectedKeyId,
            },
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Device'),
      ),
      body: BlocConsumer<DealerBloc, DealerState>(
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          if (state.nidVerificationResult != null) {
            final result = state.nidVerificationResult!;
            if (result.isValid) {
              setState(() => _nidVerified = true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('NID verified successfully'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('NID verification failed'),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
          }
          if (state.enrolledDevice != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Device enrolled successfully'),
                backgroundColor: AppTheme.successColor,
              ),
            );
            Navigator.pop(context);
          }
        },
        builder: (context, state) {
          return SingleChildScrollView(
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
                          Text(
                            'Customer Information',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _customerNameController,
                            label: 'Customer Name',
                            prefixIcon: Icons.person_outline,
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _customerPhoneController,
                            label: 'Phone Number',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _customerNIDController,
                            label: 'NID Number',
                            prefixIcon: Icons.badge_outlined,
                            maxLength: 17,
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _customerDOBController,
                            label: 'Date of Birth',
                            prefixIcon: Icons.calendar_today,
                            hint: 'YYYY-MM-DD',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: DateTime(1990),
                                firstDate: DateTime(1950),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                _customerDOBController.text =
                                    DateFormat('yyyy-MM-dd').format(date);
                                setState(() => _selectedDOB = date);
                              }
                            },
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: state.isLoading ? null : _verifyNID,
                              icon: state.isLoading
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
                                          : Icons.verified_user_outlined,
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
                          CustomTextField(
                            controller: _totalAmountController,
                            label: 'Total Amount (BDT)',
                            prefixIcon: Icons.attach_money,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v?.isEmpty ?? true) return 'Required';
                              if (double.tryParse(v!) == null) {
                                return 'Invalid amount';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          CustomTextField(
                            controller: _tenureController,
                            label: 'Tenure (Months)',
                            prefixIcon: Icons.calendar_month,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v?.isEmpty ?? true) return 'Required';
                              if (int.tryParse(v!) == null) {
                                return 'Invalid tenure';
                              }
                              return null;
                            },
                          ),
                          if (_totalAmountController.text.isNotEmpty &&
                              _tenureController.text.isNotEmpty)
                            Builder(builder: (context) {
                              final total = double.tryParse(_totalAmountController.text) ?? 0;
                              final tenure = int.tryParse(_tenureController.text) ?? 0;
                              final monthly = tenure > 0 ? total / tenure : 0;
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Monthly Installment: ৳${monthly.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        color: AppTheme.primaryColor,
                                      ),
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_generatedQRData == null)
                    ElevatedButton.icon(
                      onPressed: state.isLoading || _isGeneratingQR
                          ? null
                          : _generateQRCode,
                      icon: _isGeneratingQR
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.qr_code),
                      label: const Text('Generate QR Code'),
                    )
                  else
                    Column(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  'QR Code Generated',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: QrImageView(
                                    data: _generatedQRData!,
                                    version: QrVersions.auto,
                                    size: 200,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Customer should scan this QR code during phone setup',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: state.isLoading ? null : _submitEnrollment,
                          icon: state.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: const Text('Confirm Enrollment'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final code = barcodes.first.rawValue;
      if (code != null) {
        setState(() => _hasScanned = true);
        _processScannedCode(code);
      }
    }
  }

  Future<void> _processScannedCode(String code) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code scanned! Processing...')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
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
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  'Position the QR code within the frame',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        shadows: [
                          const Shadow(
                            blurRadius: 10,
                            color: Colors.black,
                          ),
                        ],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _scannerController.toggleTorch(),
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Toggle Flash'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}