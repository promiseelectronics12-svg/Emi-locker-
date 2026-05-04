import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../shared/theme/app_theme.dart';

class QrCodeGenerationScreen extends StatelessWidget {
  const QrCodeGenerationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device QR Code'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      'Scan to Enroll Device',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This QR code contains provisioning data for the user app',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    QrImageView(
                      data: _generateProvisioningData(context),
                      version: QrVersions.auto,
                      size: 250,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.touch_app,
                            color: AppTheme.warningColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'User must tap the screen 6 times during first boot to trigger QR enrollment mode',
                              style: TextStyle(
                                color: AppTheme.warningColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Data'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareQrCode(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Share QR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _generateProvisioningData(BuildContext context) {
    const packageName = 'com.emilocker.user';
    const downloadUrl = 'https://example.com/emilocker.apk';
    const dpcComponent = 'com.emilocker.user/.DeviceAdminReceiver';

    return 'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME=$dpcComponent;'
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION=$downloadUrl;'
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME=$packageName';
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: _generateProvisioningData(context)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR data copied to clipboard'),
        backgroundColor: AppTheme.successColor,
      ),
    );
  }

  Future<void> _shareQrCode(BuildContext context) async {
    final bytes = await QrPainter(
      data: _generateProvisioningData(context),
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    ).toImageData(300);

    if (bytes != null) {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/device_qr.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Scan this QR code to enroll your device for EMI protection',
      );
    }
  }
}