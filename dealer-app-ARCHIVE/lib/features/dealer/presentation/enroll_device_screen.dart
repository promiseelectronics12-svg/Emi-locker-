import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../auth/bloc/auth_bloc.dart';

class EnrollDeviceScreen extends StatefulWidget {
  const EnrollDeviceScreen({super.key});

  @override
  State<EnrollDeviceScreen> createState() => _EnrollDeviceScreenState();
}

class _EnrollDeviceScreenState extends State<EnrollDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerNidController = TextEditingController();
  final _customerDobController = TextEditingController();
  final _monthlyEmiController = TextEditingController();
  final _tenureController = TextEditingController();
  final _totalAmountController = TextEditingController();

  DateTime? _selectedDob;
  bool _isLoading = false;
  bool _isNidVerifying = false;
  bool _isNidVerified = false;
  bool _showQrCode = false;
  String? _generatedQrCode;
  String? _selectedKeyId;
  File? _nidImage;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerNidController.dispose();
    _customerDobController.dispose();
    _monthlyEmiController.dispose();
    _tenureController.dispose();
    _totalAmountController.dispose();
    super.dispose();
  }

  Future<void> _verifyNid() async {
    if (_customerNidController.text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid NID number'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isNidVerifying = true);

    try {
      final apiClient = ApiClient();
      final response = await apiClient.post('/dealer/verify-nid', data: {
        'nid': _customerNidController.text,
        'dob': _selectedDob?.toIso8601String(),
      });

      if (response.statusCode == 200 && response.data['verified'] == true) {
        setState(() => _isNidVerified = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NID verified successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.data['message'] ?? 'NID verification failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('NID verification failed'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }

    setState(() => _isNidVerifying = false);
  }

  Future<void> _pickNidImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() => _nidImage = File(image.path));
    }
  }

  Future<void> _selectDob() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1950),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
    );

    if (date != null) {
      setState(() {
        _selectedDob = date;
        _customerDobController.text =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _enrollDevice() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an activation key'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiClient = ApiClient();
      final authState = context.read<AuthBloc>().state;
      final userId =
          authState is AuthAuthenticated ? authState.user.id : '';

      final response = await apiClient.post('/dealer/devices/enroll', data: {
        'dealer_id': userId,
        'customer_name': _customerNameController.text.trim(),
        'customer_phone': _customerPhoneController.text.trim(),
        'customer_nid': _customerNidController.text.trim(),
        'customer_dob': _selectedDob?.toIso8601String(),
        'monthly_emi': double.parse(_monthlyEmiController.text),
        'tenure_months': int.parse(_tenureController.text),
        'total_amount': double.parse(_totalAmountController.text),
        'activation_key_id': _selectedKeyId,
        'is_nid_verified': _isNidVerified,
      });

      if (response.statusCode == 200) {
        final qrData = response.data['qr_data'] as String;
        setState(() {
          _generatedQrCode = qrData;
          _showQrCode = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(response.data['message'] ?? 'Enrollment failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enrollment failed'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  void _calculateMonthlyEmi() {
    final total = double.tryParse(_totalAmountController.text);
    final tenure = int.tryParse(_tenureController.text);

    if (total != null && tenure != null && tenure > 0) {
      final emi = total / tenure;
      _monthlyEmiController.text = emi.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll New Device'),
      ),
      body: _showQrCode
          ? _buildQrCodeView()
          : BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final user = state is AuthAuthenticated ? state.user : null;
                final availableKeys = user?.availableKeys ?? 0;

                if (availableKeys == 0) {
                  return _buildNoKeysView();
                }

                return _buildEnrollmentForm();
              },
            ),
    );
  }

  Widget _buildNoKeysView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.key_off,
              size: 80,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              'No Activation Keys',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Please purchase activation keys from your Reseller to enroll new devices.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnrollmentForm() {
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
                      'Customer Details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customerNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
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
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number *',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '01XXXXXXXXX',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter phone number';
                        }
                        if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(value)) {
                          return 'Please enter a valid BD phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _customerNidController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'NID Number *',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              if (value.length < 10) {
                                return 'Invalid NID';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isNidVerified
                              ? Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.successColor,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed:
                                      _isNidVerifying ? null : _verifyNid,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(12),
                                  ),
                                  child: _isNidVerifying
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Verify'),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customerDobController,
                            readOnly: true,
                            onTap: _selectDob,
                            decoration: const InputDecoration(
                              labelText: 'Date of Birth *',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _pickNidImage,
                          icon: const Icon(Icons.camera_alt_outlined),
                          tooltip: 'Capture NID Photo',
                        ),
                      ],
                    ),
                    if (_nidImage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: FileImage(_nidImage!),
                            fit: BoxFit.cover,
                          ),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _totalAmountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Total Amount (৳) *',
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                            onChanged: (_) => _calculateMonthlyEmi(),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              if (double.tryParse(value) == null) {
                                return 'Invalid amount';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _tenureController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Tenure (Months) *',
                              prefixIcon: Icon(Icons.calendar_month),
                            ),
                            onChanged: (_) => _calculateMonthlyEmi(),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Required';
                              }
                              final months = int.tryParse(value);
                              if (months == null || months < 1 || months > 48) {
                                return '1-48 months';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _monthlyEmiController,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Monthly EMI (৳)',
                        prefixIcon: Icon(Icons.calculate),
                        filled: true,
                        fillColor: Color(0xFFF5F5F5),
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
                      'Activation Key',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final user =
                            state is AuthAuthenticated ? state.user : null;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              hint: const Text('Select an activation key'),
                              value: _selectedKeyId,
                              items: List.generate(
                                user?.availableKeys ?? 0,
                                (index) => DropdownMenuItem(
                                  value: 'key_$index',
                                  child: Text('Key #${index + 1}'),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() => _selectedKeyId = value);
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _enrollDevice,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Generate QR Code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCodeView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 80,
              color: AppTheme.successColor,
            ),
            const SizedBox(height: 24),
            Text(
              'Device Enrolled!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Show this QR code to the customer to complete enrollment.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_generatedQrCode != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: _generatedQrCode!,
                  version: QrVersions.auto,
                  size: 250,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Customer must scan this QR during phone setup',
              style: TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _showQrCode = false;
                      _generatedQrCode = null;
                    });
                    _clearForm();
                  },
                  child: const Text('Enroll Another'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _clearForm() {
    _customerNameController.clear();
    _customerPhoneController.clear();
    _customerNidController.clear();
    _customerDobController.clear();
    _monthlyEmiController.clear();
    _tenureController.clear();
    _totalAmountController.clear();
    setState(() {
      _selectedDob = null;
      _isNidVerified = false;
      _nidImage = null;
      _selectedKeyId = null;
    });
  }
}
