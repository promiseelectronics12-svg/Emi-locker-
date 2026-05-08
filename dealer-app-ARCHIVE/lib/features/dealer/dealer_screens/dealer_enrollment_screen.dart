import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/activation_key_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class DealerEnrollmentScreen extends StatefulWidget {
  final bool scannerMode;

  const DealerEnrollmentScreen({
    super.key,
    this.scannerMode = false,
  });

  @override
  State<DealerEnrollmentScreen> createState() => _DealerEnrollmentScreenState();
}

class _DealerEnrollmentScreenState extends State<DealerEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidController = TextEditingController();
  final _dobController = TextEditingController();
  final _dobTextController = TextEditingController();
  final _qrDataController = TextEditingController();

  List<ActivationKey> _availableKeys = [];
  ActivationKey? _selectedKey;
  String? _nidFrontPath;
  String? _nidBackPath;
  bool _isLoading = false;
  bool _nidVerified = false;
  bool _showQR = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableKeys();
    if (widget.scannerMode) {
      _showQR = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nidController.dispose();
    _dobController.dispose();
    _dobTextController.dispose();
    _qrDataController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableKeys() async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/activation-keys',
          queryParameters: {
            'dealer_id': authState.user!.id,
            'is_used': false,
          },
        );
        final data = response.data as Map<String, dynamic>;
        final keysJson = data['keys'] as List<dynamic>;
        setState(() {
          _availableKeys = keysJson
              .map((json) => ActivationKey.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load keys: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickNIDImage(bool isFront) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        if (isFront) {
          _nidFrontPath = image.path;
        } else {
          _nidBackPath = image.path;
        }
      });
    }
  }

  Future<void> _verifyNID() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = context.read<ApiClient>();
      final response = await apiClient.post(
        '/nid/verify',
        data: {
          'nid_number': _nidController.text.trim(),
          'dob': _dobTextController.text.trim(),
          'name': _nameController.text.trim(),
        },
      );
      final data = response.data as Map<String, dynamic>;
      if (data['verified'] == true) {
        setState(() => _nidVerified = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NID verified successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _nidVerified = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NID verification failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _nidVerified = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NID verification error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _enrollDevice() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an activation key'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        await apiClient.post(
          '/devices/enroll',
          data: {
            'dealer_id': authState.user!.id,
            'activation_key_id': _selectedKey!.id,
            'customer_name': _nameController.text.trim(),
            'customer_phone': _phoneController.text.trim(),
            'customer_nid': _nidController.text.trim(),
            'customer_dob': _dobTextController.text.trim(),
            'nid_verified': _nidVerified,
            'enrollment_timestamp': DateTime.now().toIso8601String(),
          },
        );

        if (mounted) {
          _showQRCodeDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enrollment failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showQRCodeDialog() {
    final authState = context.read<AuthBloc>().state;
    String qrData = '';
    if (authState is AuthAuthenticated) {
      qrData = _qrDataController.text.isNotEmpty
          ? _qrDataController.text
          : 'https://api.emilocker.com/provision?dealer=${authState.user!.id}&key=${_selectedKey!.id}';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Device Enrollment QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Show this QR code to the customer for enrollment',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Activation Key: ${_selectedKey!.keyCode}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForm();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    _nameController.clear();
    _phoneController.clear();
    _nidController.clear();
    _dobController.clear();
    _dobTextController.clear();
    setState(() {
      _selectedKey = null;
      _nidFrontPath = null;
      _nidBackPath = null;
      _nidVerified = false;
      _showQR = false;
    });
    _loadAvailableKeys();
  }

  Future<void> _scanQRCode() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Scan Enrollment QR'),
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  final code = barcode.rawValue!;
                  if (code.startsWith('http')) {
                    _qrDataController.text = code;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Scanned: ${_qrDataController.text}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    break;
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.scannerMode ? 'Scan QR Code' : 'Enroll New Device'),
        actions: [
          if (!widget.scannerMode)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {
                setState(() => _showQR = !_showQR);
                if (_showQR) {
                  _scanQRCode();
                }
              },
            ),
        ],
      ),
      body: _showQR
          ? _buildQRDisplay()
          : _buildEnrollmentForm(),
    );
  }

  Widget _buildQRDisplay() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_qrDataController.text.isNotEmpty) ...[
            QrImageView(
              data: _qrDataController.text,
              version: QrVersions.auto,
              size: 250.0,
            ),
            const SizedBox(height: 16),
            Text(
              'Scanned Data: ${_qrDataController.text}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _showQR = false;
                  _qrDataController.clear();
                });
              },
              child: const Text('Enter Manually'),
            ),
          ] else ...[
            const Icon(Icons.qr_code_scanner, size: 100, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Tap the scanner icon to scan QR code',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                setState(() => _showQR = false);
              },
              child: const Text('Enter Manually'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnrollmentForm() {
    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'Processing...',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_availableKeys.isEmpty)
                Card(
                  color: Colors.orange[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[700]),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'No activation keys available. Purchase keys from your reseller.',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                const Text(
                  'Select Activation Key',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ActivationKey>(
                  value: _selectedKey,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.vpn_key),
                    hintText: 'Select an available key',
                  ),
                  items: _availableKeys.map((key) {
                    return DropdownMenuItem(
                      value: key,
                      child: Text('${key.keyCode} - Unused'),
                    );
                  }).toList(),
                  onChanged: (key) {
                    setState(() => _selectedKey = key);
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select an activation key';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Customer Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: Validators.validateName,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  prefixIcon: Icon(Icons.person_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: Validators.validatePhone,
                decoration: const InputDecoration(
                  labelText: 'Customer Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '01XXXXXXXXX',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nidController,
                keyboardType: TextInputType.number,
                validator: Validators.validateNID,
                decoration: const InputDecoration(
                  labelText: 'NID Number',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dobTextController,
                readOnly: true,
                validator: Validators.validateDateOfBirth,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now().subtract(const Duration(days: 6570)),
                  );
                  if (date != null) {
                    _dobTextController.text = Validators.formatDate(date);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Date of Birth',
                  prefixIcon: const Icon(Icons.cake_outlined),
                  hintText: 'DD/MM/YYYY',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime(2000),
                        firstDate: DateTime(1950),
                        lastDate: DateTime.now().subtract(const Duration(days: 6570)),
                      );
                      if (date != null) {
                        _dobTextController.text = Validators.formatDate(date);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _nidVerified ? null : _verifyNID,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _nidVerified ? Colors.green : AppTheme.primaryColor,
                      ),
                      icon: Icon(_nidVerified ? Icons.check : Icons.verified),
                      label: Text(_nidVerified ? 'Verified' : 'Verify NID (10 BDT)'),
                    ),
                  ),
                ],
              ),
              if (_nidVerified) ...[
                const SizedBox(height: 8),
                Text(
                  'NID has been verified',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'NID Photos (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NIDPhotoCard(
                      label: 'Front',
                      imagePath: _nidFrontPath,
                      onTap: () => _pickNIDImage(true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NIDPhotoCard(
                      label: 'Back',
                      imagePath: _nidBackPath,
                      onTap: () => _pickNIDImage(false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _availableKeys.isEmpty ? null : _enrollDevice,
                child: const Text('Proceed to QR Generation'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _NIDPhotoCard extends StatelessWidget {
  final String label;
  final String? imagePath;
  final VoidCallback onTap;

  const _NIDPhotoCard({
    required this.label,
    this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: imagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      imagePath!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image,
                        size: 40,
                        color: Colors.grey,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, color: Colors.grey[400], size: 32),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}