import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/config/env_config.dart';
import '../../shared/theme/app_theme.dart';

class ProvisioningQrScreen extends StatelessWidget {
  final String enrollmentToken;

  const ProvisioningQrScreen({super.key, required this.enrollmentToken});

  @override
  Widget build(BuildContext context) {
    final String amapiJson = jsonEncode({
      "android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME":
          "com.android.simtoolkit/com.android.simtoolkit.receiver.DeviceAdminReceiver",
      "android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION":
          "${EnvConfig.apiBaseUrl}/download/user-app.apk",
      "android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE": {
        "enrollmentToken": enrollmentToken,
        "apiBaseUrl": EnvConfig.apiBaseUrl,
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisioning QR Code'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                child: Text(
                  'Scan this QR code during the phone setup wizard.\n\nTap the screen 6 times in the setup wizard to open the QR scanner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: amapiJson,
                  version: QrVersions.auto,
                  size: 280.0,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enrollment Token: $enrollmentToken',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

