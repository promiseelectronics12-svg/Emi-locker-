import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';

class NeirExportScreen extends StatefulWidget {
  const NeirExportScreen({super.key});

  @override
  State<NerExportScreen> createState() => _NerExportScreenState();
}

class _NerExportScreenState extends State<NerExportScreen> {
  final ApiClient _apiClient = ApiClient();
  List<Device> _devices = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _exportStatus = '';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/dealer/devices');
      if (response.statusCode == 200) {
        final List<dynamic> devicesJson = response.data['devices'] ?? [];
        _devices = devicesJson
            .map((json) => Device.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load devices'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToExcel() async {
    if (_devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No devices to export'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportStatus = 'Generating Excel file...';
    });

    try {
      final excel = Excel.createExcel();
      final sheet = excel['NEIR_Export'];

      final headers = [
        'SL No',
        'IMEI 1',
        'IMEI 2',
        'MAC Address',
        'Customer Name',
        'Customer Phone',
        'Customer NID',
        'Enrollment Date',
        'Total Amount',
        'Monthly EMI',
        'Tenure (Months)',
        'Paid Months',
        'Outstanding Amount',
        'Device Status',
      ];

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, row: 0)).value =
            TextCellValue(headers[i]);
      }

      final dateFormat = DateFormat('yyyy-MM-dd');
      int slNo = 1;

      for (final device in _devices) {
        final rowIndex = slNo;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, row: rowIndex)).value =
            IntCellValue(slNo);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, row: rowIndex)).value =
            TextCellValue(device.imei1);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, row: rowIndex)).value =
            TextCellValue(device.imei2 ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, row: rowIndex)).value =
            TextCellValue(device.macAddress ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, row: rowIndex)).value =
            TextCellValue(device.customerName);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, row: rowIndex)).value =
            TextCellValue(device.customerPhone);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, row: rowIndex)).value =
            TextCellValue(device.customerNid ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, row: rowIndex)).value =
            TextCellValue(dateFormat.format(device.enrollmentDate));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, row: rowIndex)).value =
            TextCellValue(device.totalAmount.toStringAsFixed(2));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, row: rowIndex)).value =
            TextCellValue(device.monthlyEmi.toStringAsFixed(2));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, row: rowIndex)).value =
            IntCellValue(device.tenureMonths);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, row: rowIndex)).value =
            IntCellValue(device.paidMonths);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, row: rowIndex)).value =
            TextCellValue(device.remainingAmount.toStringAsFixed(2));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, row: rowIndex)).value =
            TextCellValue(device.statusDisplayName);

        slNo++;
      }

      setState(() => _exportStatus = 'Saving file...');

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'NEIR_Export_$timestamp.xlsx';
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      }

      setState(() => _exportStatus = 'File saved successfully');

      if (mounted) {
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'NEIR Export - ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
        );
      }

      setState(() {
        _isExporting = false;
        _exportStatus = '';
      });
    } catch (e) {
      setState(() {
        _isExporting = false;
        _exportStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
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
        title: const Text('NEIR Export'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.description_outlined,
                            size: 64,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'BTRC NEIR Export',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Generate Excel file for BTRC device registration',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                            textAlign: TextAlign.center,
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
                            'Export Summary',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          _buildSummaryRow('Total Devices', '${_devices.length}'),
                          _buildSummaryRow(
                            'Active',
                            '${_devices.where((d) => d.status == DeviceStatus.active).length}',
                          ),
                          _buildSummaryRow(
                            'Locked',
                            '${_devices.where((d) => d.status == DeviceStatus.locked).length}',
                          ),
                          _buildSummaryRow(
                            'Decoupled',
                            '${_devices.where((d) => d.status == DeviceStatus.decoupled).length}',
                          ),
                          const Divider(),
                          _buildSummaryRow(
                            'Total Outstanding',
                            '৳${_devices.fold<double>(0, (sum, d) => sum + d.remainingAmount).toStringAsFixed(0)}',
                            isHighlighted: true,
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
                            'Export Contents',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'The exported file will include:',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          _buildContentItem('• Device IMEIs (Primary & Secondary)'),
                          _buildContentItem('• MAC Address'),
                          _buildContentItem('• Customer Information'),
                          _buildContentItem('• EMI Schedule Details'),
                          _buildContentItem('• Payment Status'),
                          _buildContentItem('• Device Current Status'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isExporting) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _exportStatus,
                      style: const TextStyle(color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ElevatedButton.icon(
                    onPressed: _isExporting ? null : _exportToExcel,
                    icon: const Icon(Icons.download),
                    label: const Text('Export to Excel'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'File will be shared for download after generation',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isHighlighted ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
              color: isHighlighted ? AppTheme.primaryColor : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
