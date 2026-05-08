import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/activation_key.dart';
import '../../../shared/models/device.dart';

class EnrollDevicePage extends StatefulWidget {
  const EnrollDevicePage({super.key});

  @override
  State<EnrollDevicePage> createState() => _EnrollDevicePageState();
}

class _EnrollDevicePageState extends State<EnrollDevicePage>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerNidController = TextEditingController();
  final _customerDobController = TextEditingController();

  List<ActivationKey> _availableKeys = [];
  ActivationKey? _selectedKey;
  bool _isLoading = false;
  bool _isNidVerifying = false;
  bool _isNidVerified = false;
  String? _nidError;
  XFile? _nidFrontImage;
  XFile? _nidBackImage;

  String? _generatedQrData;
  bool _isQrMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAvailableKeys();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerNidController.dispose();
    _customerDobController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableKeys() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/activation-keys/available');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['keys'] as List<dynamic>;
        setState(() {
          _availableKeys = data
              .map((json) => ActivationKey.fromJson(json as Map<String, dynamic>))
              .where((key) => key.isAvailable)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load activation keys'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyNid() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isNidVerifying = true;
      _isNidVerified = false;
      _nidError = null;
    });

    try {
      final response = await _apiClient.post('/nid/verify', data: {
        'nid_number': _customerNidController.text.trim(),
        'dob': _customerDobController.text.trim(),
        'name': _customerNameController.text.trim(),
      });

      if (response.statusCode == 200 && response.data['verified'] == true) {
        setState(() => _isNidVerified = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NID verified successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _nidError = 'NID verification failed. Please check the details.';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_nidError!),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isNidVerifying = false);
    }
  }

  Future<void> _captureNidImages() async {
    final frontImage = await _imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (frontImage != null) {
      setState(() => _nidFrontImage = frontImage);
    }

    final backImage = await _imagePicker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (backImage != null) {
      setState(() => _nidBackImage = backImage);
    }
  }

  Future<void> _generateQrCode() async {
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an activation key'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.post('/devices/enroll/initiate', data: {
        'customer_name': _customerNameController.text.trim(),
        'customer_phone': _customerPhoneController.text.trim(),
        'customer_nid': _customerNidController.text.trim(),
        'customer_dob': _customerDobController.text.trim(),
        'activation_key_id': _selectedKey!.id,
        'nid_verified': _isNidVerified,
      });

      if (response.statusCode == 200) {
        final qrData = response.data['qr_data'] as String;
        setState(() {
          _generatedQrData = qrData;
          _isQrMode = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate QR code'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Device'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Manual Entry'),
            Tab(text: 'Scan IMEI'),
          ],
        ),
        actions: [
          if (_isQrMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isQrMode = false;
                  _generatedQrData = null;
                });
              },
            ),
        ],
      ),
      body: _isQrMode
          ? _buildQrDisplay()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildManualEntryTab(),
                _buildScanImeiTab(),
              ],
            ),
    );
  }

  Widget _buildManualEntryTab() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Customer Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter customer name';
                      }
                      if (value.length < 2) {
                        return 'Name must be at least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter phone number';
                      }
                      if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(value)) {
                        return 'Please enter a valid Bangladeshi phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerNidController,
                    decoration: const InputDecoration(
                      labelText: 'NID Number',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter NID number';
                      }
                      if (value.length != 10 && value.length != 13) {
                        return 'NID must be 10 or 13 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customerDobController,
                    decoration: const InputDecoration(
                      labelText: 'Date of Birth',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      hintText: 'YYYY-MM-DD',
                    ),
                    keyboardType: TextInputType.datetime,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter date of birth';
                      }
                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
                        return 'Please enter date in YYYY-MM-DD format';
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'NID Verification',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_isNidVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Verified',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cost: 10 BDT',
                    style: TextStyle(
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isNidVerified) ...[
                    ElevatedButton.icon(
                      onPressed: _isNidVerifying ? null : _verifyNid,
                      icon: _isNidVerifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_user_outlined),
                      label: Text(
                        _isNidVerifying ? 'Verifying...' : 'Verify NID',
                      ),
                    ),
                    if (_nidError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _nidError!,
                        style: const TextStyle(
                          color: AppTheme.errorColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ] else ...[
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppTheme.successColor,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'NID verified against government database',
                          style: TextStyle(
                            color: AppTheme.successColor,
                          ),
                        ),
                      ],
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
                  const Text(
                    'Activation Key',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_availableKeys.isEmpty)
                    const Center(
                      child: Text(
                        'No activation keys available.\nPlease purchase keys from your reseller.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondaryColor),
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<ActivationKey>(
                      value: _selectedKey,
                      decoration: const InputDecoration(
                        labelText: 'Select Key',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                      items: _availableKeys.map((key) {
                        return DropdownMenuItem(
                          value: key,
                          child: Text(
                            '${key.key} (Expires: ${key.expiresAt.toString().split(' ')[0]})',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedKey = value);
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Please select an activation key';
                        }
                        return null;
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _generateQrCode,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('Generate QR Code'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanImeiTab() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _handleScannedImei(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black87,
          child: const Column(
            children: [
              Text(
                'Point camera at barcode or QR code',
                style: TextStyle(color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(
                'IMEI should be scanned from device box or label',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleScannedImei(String scannedData) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Scanned: $scannedData'),
      ),
    );
  }

  Widget _buildQrDisplay() {
    if (_generatedQrData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _generatedQrData!,
                version: QrVersions.auto,
                size: 280,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Scan this QR code on the customer\'s phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Customer should tap the screen 6 times during first boot to trigger QR enrollment mode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isQrMode = false;
                  _generatedQrData = null;
                  _customerNameController.clear();
                  _customerPhoneController.clear();
                  _customerNidController.clear();
                  _customerDobController.clear();
                  _selectedKey = null;
                  _isNidVerified = false;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Enroll Another Device'),
            ),
          ],
        ),
      ),
    );
  }
}