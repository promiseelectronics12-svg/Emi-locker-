import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/activation_key_model.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  int _currentStep = 0;
  final _customerNameController = TextEditingController();
  final _customerNidController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _imeiController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _monthlyAmountController = TextEditingController();
  final _totalMonthsController = TextEditingController();
  String? _nidPhotoPath;
  String? _selectedKeyId;
  List<ActivationKeyModel> _availableKeys = [];
  bool _loading = false;
  String? _generatedQrData;

  @override
  void initState() {
    super.initState();
    _loadAvailableKeys();
  }

  Future<void> _loadAvailableKeys() async {
    try {
      final response = await Injection.apiClient.get(
        '/api/v1/keys/my?status=available',
      );
      setState(() {
        _availableKeys = (response.data as List)
            .map((e) => ActivationKeyModel.fromJson(e))
            .toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerNidController.dispose();
    _customerPhoneController.dispose();
    _imeiController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _monthlyAmountController.dispose();
    _totalMonthsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll New Device')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _nextStep,
        onStepCancel: _currentStep > 0
            ? () => setState(() => _currentStep--)
            : null,
        steps: [
          Step(
            title: const Text('Customer Details'),
            content: _buildCustomerStep(),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: const Text('Device Info'),
            content: _buildDeviceStep(),
            isActive: _currentStep >= 1,
          ),
          Step(
            title: const Text('EMI Terms'),
            content: _buildEmiStep(),
            isActive: _currentStep >= 2,
          ),
          Step(
            title: const Text('Review'),
            content: _buildReviewStep(),
            isActive: _currentStep >= 3,
          ),
          Step(
            title: const Text('QR Provisioning'),
            content: _buildQrStep(),
            isActive: _currentStep >= 4,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerStep() {
    return Column(
      children: [
        TextField(
          controller: _customerNameController,
          decoration: const InputDecoration(
            labelText: 'Customer Name',
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customerNidController,
          decoration: const InputDecoration(
            labelText: 'NID Number',
            prefixIcon: Icon(Icons.credit_card),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customerPhoneController,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            prefixIcon: Icon(Icons.phone),
            prefixText: '+880 ',
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _pickNidPhoto,
          icon: const Icon(Icons.camera_alt),
          label: Text(
            _nidPhotoPath == null ? 'Capture NID Photo' : 'NID Photo Captured',
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceStep() {
    return Column(
      children: [
        TextField(
          controller: _imeiController,
          decoration: InputDecoration(
            labelText: 'IMEI Number',
            prefixIcon: const Icon(Icons.phone_android),
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scanImei,
            ),
          ),
          keyboardType: TextInputType.number,
          maxLength: 15,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _brandController,
          decoration: const InputDecoration(
            labelText: 'Brand',
            prefixIcon: Icon(Icons.branding_watermark),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _modelController,
          decoration: const InputDecoration(
            labelText: 'Model',
            prefixIcon: Icon(Icons.phone_iphone),
          ),
        ),
      ],
    );
  }

  Widget _buildEmiStep() {
    return Column(
      children: [
        TextField(
          controller: _monthlyAmountController,
          decoration: const InputDecoration(
            labelText: 'Monthly Amount (BDT)',
            prefixIcon: Icon(Icons.attach_money),
            prefixText: '৳ ',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _totalMonthsController,
          decoration: const InputDecoration(
            labelText: 'Total Months',
            prefixIcon: Icon(Icons.calendar_month),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        if (_availableKeys.isNotEmpty)
          DropdownButtonFormField<String>(
            value: _selectedKeyId,
            decoration: const InputDecoration(
              labelText: 'Activation Key',
              prefixIcon: Icon(Icons.vpn_key),
            ),
            items: _availableKeys.map((key) {
              return DropdownMenuItem(
                value: key.id,
                child: Text(key.key.substring(0, 8) + '...'),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedKeyId = val),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No activation keys available. Purchase keys from your reseller.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer', style: Theme.of(context).textTheme.titleMedium),
            _reviewRow('Name', _customerNameController.text),
            _reviewRow('NID', _customerNidController.text),
            _reviewRow('Phone', '+880 ${_customerPhoneController.text}'),
            const Divider(),
            Text('Device', style: Theme.of(context).textTheme.titleMedium),
            _reviewRow('IMEI', _imeiController.text),
            _reviewRow('Brand', _brandController.text),
            _reviewRow('Model', _modelController.text),
            const Divider(),
            Text('EMI', style: Theme.of(context).textTheme.titleMedium),
            _reviewRow('Monthly', '৳${_monthlyAmountController.text}'),
            _reviewRow('Duration', '${_totalMonthsController.text} months'),
            if (_selectedKeyId != null)
              _reviewRow('Key', _selectedKeyId!.substring(0, 8) + '...'),
          ],
        ),
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildQrStep() {
    if (_generatedQrData == null) {
      return const Center(child: Text('Submit enrollment first'));
    }
    return Column(
      children: [
        Text(
          'Scan this QR code during device setup',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'On the phone\'s first boot wizard, tap the screen 6 times to enter QR enrollment mode',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        QrImageView(
          data: _generatedQrData!,
          size: 250,
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 24),
        const Card(
          color: Color(0xFFE8F5E9),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enrollment submitted. After QR scan, the device will install our app automatically with Device Owner privileges.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickNidPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _nidPhotoPath = image.path);
    }
  }

  void _scanImei() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan IMEI')),
          body: MobileScanner(
            onCapture: (capture) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) {
                setState(() => _imeiController.text = code);
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
    );
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_customerNameController.text.isEmpty ||
          _customerNidController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill customer details')),
        );
        return;
      }
    } else if (_currentStep == 1) {
      if (_imeiController.text.length != 15) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IMEI must be 15 digits')));
        return;
      }
    } else if (_currentStep == 2) {
      if (_monthlyAmountController.text.isEmpty ||
          _totalMonthsController.text.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please fill EMI terms')));
        return;
      }
    } else if (_currentStep == 3) {
      _submitEnrollment();
      return;
    }
    setState(() => _currentStep++);
  }

  Future<void> _submitEnrollment() async {
    setState(() => _loading = true);
    try {
      final response = await Injection.apiClient.post(
        '/api/v1/enrollments',
        data: {
          'customer_name': _customerNameController.text,
          'customer_nid': _customerNidController.text,
          'customer_phone': _customerPhoneController.text,
          'imei': _imeiController.text,
          'brand': _brandController.text,
          'model': _modelController.text,
          'monthly_amount': double.parse(_monthlyAmountController.text),
          'total_months': int.parse(_totalMonthsController.text),
          'activation_key_id': _selectedKeyId,
        },
      );

      final provisioningUrl = EnvConfig.qrProvisioningUrl;
      final deviceId = response.data['device_id'] ?? '';
      setState(() {
        _generatedQrData = '$provisioningUrl?device_id=$deviceId';
        _currentStep = 4;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Enrollment failed: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }
}
