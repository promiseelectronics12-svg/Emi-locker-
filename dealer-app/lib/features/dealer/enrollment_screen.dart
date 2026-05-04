import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:convert';
import '../../shared/config/env_config.dart';
import '../auth/auth_bloc.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nidController = TextEditingController();
  XFile? _nidImage;
  String? _qrData;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    setState(() => _nidImage = image);
  }

  void _generateQr() {
    if (_formKey.currentState!.validate()) {
      final authState = context.read<AuthBloc>().state;
      final dealerId = authState.user?.id ?? 'UNKNOWN';

      // Data structure for AMAPI QR Provisioning
      final Map<String, dynamic> provisioningData = {
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME": 
            "com.emilocker.userapp/com.emilocker.userapp.receiver.DeviceAdminReceiver",
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION": 
            "${EnvConfig.apiBaseUrl}/download/user-app.apk",
        "android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM": 
            "YOUR_APK_SIGNATURE_CHECKSUM_HERE", // Replace with actual SHA-256 hash of the APK
        "android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED": true,
        "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE": {
          "dealerId": dealerId,
          "customerName": _nameController.text,
          "customerPhone": _phoneController.text,
          "customerNid": _nidController.text,
          "apiBaseUrl": EnvConfig.apiBaseUrl,
        }
      };

      setState(() {
        _qrData = jsonEncode(provisioningData);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll New Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_qrData == null) ...[
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder()),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Customer Phone', border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nidController,
                      decoration: const InputDecoration(labelText: 'NID Number', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.camera_alt),
                label: Text(_nidImage == null ? 'Capture NID Photo' : 'NID Photo Captured'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _nidImage == null ? Colors.blue : Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _generateQr,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                ),
                child: const Text('GENERATE ENROLLMENT QR'),
              ),
            ] else ...[
              const Text(
                'Scan this QR on the target device',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the setup screen 6 times to start QR scanner',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Center(
                child: QrImageView(
                  data: _qrData!,
                  version: QrVersions.auto,
                  size: 300.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () => setState(() => _qrData = null),
                child: const Text('BACK'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
