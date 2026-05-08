import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/analytics_service.dart';
import '../../../shared/theme/app_theme.dart';

class NeireExportScreen extends StatefulWidget {
  const NeireExportScreen({super.key});

  @override
  State<NeireExportScreen> createState() => _NeireExportScreenState();
}

class _NeireExportScreenState extends State<NeireExportScreen> {
  late final AnalyticsService _analyticsService;
  bool _isExporting = false;
  String? _lastExportPath;
  String? _error;
  int _deviceCount = 0;

  @override
  void initState() {
    super.initState();
    _analyticsService = AnalyticsService(ApiClient());
  }

  Future<void> _exportForBtrc() async {
    setState(() {
      _isExporting = true;
      _error = null;
      _lastExportPath = null;
    });

    try {
      final file = await _analyticsService.generateNeirExcel();
      setState(() {
        _lastExportPath = file.path;
        _isExporting = false;
      });

      if (mounted) {
        _showExportSuccessDialog(file);
      }
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isExporting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to generate NEIR export. Please try again.';
        _isExporting = false;
      });
    }
  }

  Future<void> _shareExport() async {
    if (_lastExportPath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(_lastExportPath!)],
        text: 'NEIR Export - EMI Locker Platform - ${DateTime.now().toString().split(' ')[0]}',
        subject: 'NEIR Export for BTRC',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share file'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showExportSuccessDialog(File file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.successColor),
            SizedBox(width: 8),
            Text('Export Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your NEIR Excel file has been generated successfully.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File saved to:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.path,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Next Steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('1. Open the Excel file to verify the data'),
            const Text('2. Email the file to: neir@btrc.gov.bd'),
            const Text('3. Keep a copy for your records'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _shareExport();
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEIR Export'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.file_present,
                      size: 64,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Export for BTRC NEIR',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Generate an Excel file with all your enrolled device IMEIs in the format required by BTRC.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BTRC Required Format',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'The exported file will include: IMEI, Device Brand, Model, Dealer NID, Dealer Business Name, and Registration Date.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.errorColor),
                      ),
                    ),
                  ],
                ),
              ),
            if (_lastExportPath != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.successColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.successColor),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Export completed successfully!',
                        style: TextStyle(color: AppTheme.successColor),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isExporting ? null : _exportForBtrc,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.dealerColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.file_download),
                label: Text(_isExporting ? 'Generating...' : 'Export for BTRC NEIR'),
              ),
            ),
            const SizedBox(height: 16),
            if (_lastExportPath != null)
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _shareExport,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dealerColor,
                    side: const BorderSide(color: AppTheme.dealerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Share/Download'),
                ),
              ),
            const SizedBox(height: 32),
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.email, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Submission Instructions',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'After generating the Excel file:',
                      style: TextStyle(color: Colors.orange[900]),
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Download or share the file to your device'),
                    const Text('2. Open and verify the data in Excel'),
                    const Text('3. Email this file to:'),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: const Text(
                        'neir@btrc.gov.bd',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('4. Use "NEIR Export" as the email subject'),
                    const Text('5. Keep records of all submissions'),
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
                      'What is NEIR?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'NEIR (National Equipment Identity Register) is a BTRC-mandated database for tracking mobile devices in Bangladesh. All mobile phone dealers are required to register their device inventory.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}