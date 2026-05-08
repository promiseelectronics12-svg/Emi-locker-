import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/activation_key.dart';
import '../auth/auth_bloc.dart';
import '../auth/auth_event_state.dart';

class EnrollDeviceScreen extends StatefulWidget {
  const EnrollDeviceScreen({super.key});

  @override
  State<EnrollDeviceScreen> createState() => _EnrollDeviceScreenState();
}

class _EnrollDeviceScreenState extends State<EnrollDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiClient = ApiClient();
  final _imagePicker = ImagePicker();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidController = TextEditingController();

  DateTime? _dateOfBirth;
  ActivationKey? _selectedKey;
  List<ActivationKey> _availableKeys = [];
  bool _isLoading = false;
  bool _isNidVerified = false;
  bool _isVerifyingNid = false;
  String? _nidError;
  XFile? _nidPhoto;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _loadActivationKeys();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nidController.dispose();
    super.dispose();
  }

  Future<void> _loadActivationKeys() async {
    final authState = context.read<AuthBloc>().state;
    try {
      final response = await _apiClient.get(
        '/activation-keys',
        queryParameters: {
          'dealer_id': authState.user?.id,
          'is_used': false,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['keys'] ?? [];
        setState(() {
          _availableKeys = data.map((json) => ActivationKey.fromJson(json)).toList();
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _verifyNid() async {
    if (_nidController.text.length != 10 && _nidController.text.length != 13) {
      setState(() {
        _nidError = 'NID must be 10 or 13 digits';
      });
      return;
    }

    setState(() {
      _isVerifyingNid = true;
      _nidError = null;
    });

    try {
      final response = await _apiClient.post('/verify-nid', data: {
        'nid': _nidController.text,
        'dob': _dateOfBirth?.toIso8601String(),
      });

      if (response.statusCode == 200 && response.data['valid'] == true) {
        setState(() {
          _isNidVerified = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NID verified successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        setState(() {
          _nidError = 'NID verification failed';
        });
      }
    } catch (e) {
      setState(() {
        _nidError = 'NID verification service unavailable';
      });
    } finally {
      setState(() {
        _isVerifyingNid = false;
      });
    }
  }

  Future<void> _pickNidPhoto(ImageSource source) async {
    final photo = await _imagePicker.pickImage(source: source, imageQuality: 80);
    if (photo != null) {
      setState(() {
        _nidPhoto = photo;
      });
    }
  }

  void _handleEnroll() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedKey == null) {
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
      final response = await _apiClient.post('/devices/enroll', data: {
        'dealer_id': context.read<AuthBloc>().state.user?.id,
        'key_id': _selectedKey!.id,
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'customer_nid': _nidController.text.trim(),
        'customer_dob': _dateOfBirth?.toIso8601String(),
      });

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device enrolled successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enrollment failed: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll New Device'),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              if (_currentStep == 0 && _selectedKey == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select an activation key')),
                );
                return;
              }
              setState(() => _currentStep++);
            } else {
              _handleEnroll();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  if (_currentStep < 2)
                    ElevatedButton(
                      onPressed: details.onStepContinue,
                      child: const Text('Continue'),
                    )
                  else
                    ElevatedButton(
                      onPressed: _isLoading ? null : details.onStepContinue,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enroll Device'),
                    ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                  ),
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Select Activation Key'),
              content: _buildKeySelection(),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: const Text('Customer Details'),
              content: _buildCustomerDetails(),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            ),
            Step(
              title: const Text('Review & Enroll'),
              content: _buildReview(),
              isActive: _currentStep >= 2,
              state: StepState.indexed,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeySelection() {
    if (_availableKeys.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No activation keys available. Please purchase keys from your reseller.'),
      );
    }

    return Column(
      children: [
        ..._availableKeys.map((key) => RadioListTile<ActivationKey>(
              title: Text('Key: ${key.keyCode}'),
              subtitle: Text('Created: ${key.createdAt.toString().split(' ')[0]}'),
              value: key,
              groupValue: _selectedKey,
              onChanged: (value) => setState(() => _selectedKey = value),
            )),
      ],
    );
  }

  Widget _buildCustomerDetails() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Customer Name',
            prefixIcon: Icon(Icons.person_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name is required';
            }
            if (value.trim().length < 2) {
              return 'Name must be at least 2 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            prefixIcon: Icon(Icons.phone_outlined),
            hintText: '01XXXXXXXXX',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Phone number is required';
            }
            if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(value.trim())) {
              return 'Enter a valid Bangladeshi phone number';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nidController,
          keyboardType: TextInputType.number,
          maxLength: 13,
          enabled: !_isNidVerified,
          decoration: const InputDecoration(
            labelText: 'NID Number',
            prefixIcon: Icon(Icons.badge_outlined),
            counterText: '',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'NID is required';
            }
            if (value.length != 10 && value.length != 13) {
              return 'NID must be 10 or 13 digits';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(2000),
              firstDate: DateTime(1950),
              lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
            );
            if (date != null) {
              setState(() => _dateOfBirth = date);
            }
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date of Birth',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            child: Text(
              _dateOfBirth != null
                  ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                  : 'Select Date',
              style: TextStyle(
                color: _dateOfBirth != null ? null : Colors.grey,
              ),
            ),
          ),
        ),
        if (_nidError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _nidError!,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isNidVerified
                    ? null
                    : () => _pickNidPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isNidVerified
                    ? null
                    : () => _pickNidPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        if (_nidPhoto != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.successColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Photo selected',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isNidVerified || _isVerifyingNid ? null : _verifyNid,
            icon: _isVerifyingNid
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isNidVerified ? Icons.check_circle : Icons.verified_user,
                    color: Colors.white,
                  ),
            label: Text(_isNidVerified ? 'NID Verified' : 'Verify NID (10 BDT)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isNidVerified ? AppTheme.successColor : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                _reviewRow('Activation Key', _selectedKey?.keyCode ?? 'N/A'),
                _reviewRow('Customer Name', _nameController.text),
                _reviewRow('Phone', _phoneController.text),
                _reviewRow('NID', _nidController.text),
                _reviewRow('DOB', _dateOfBirth != null
                    ? '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'
                    : 'N/A'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Next: Scan QR code on the customer\'s device to complete enrollment',
          style: TextStyle(color: Colors.grey),
        ),
      ],
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
}