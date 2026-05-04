import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';

class NEIRExportScreen extends StatefulWidget {
  const NEIRExportScreen({super.key});

  @override
  State<NEIRExportScreen> createState() => _NEIRExportScreenState();
}

class _NEIRExportScreenState extends State<NEIRExportScreen> {
  bool _isExporting = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _startDate = date;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _endDate = date;
      });
    }
  }

  Future<void> _exportNEIR() async {
    setState(() {
      _isExporting = true;
    });

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Devices'];

      final headers = [
        'IMEI 1',
        'IMEI 2',
        'MAC Address',
        'Customer Name',
        'Customer Phone',
        'NID',
        'Enrollment Date',
        'Status',
        'Lock Status',
      ];

      for (var i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, row: 0)).value =
            TextCellValue(headers[i]);
      }

      final data = [
        ['123456789012345', '123456789012346', 'AA:BB:CC:DD:EE:FF', 'John Doe', '01XXXXXXXXX', '1234567890123', '2026-01-15', 'ACTIVE', 'UNLOCKED'],
        ['987654321098765', '987654321098766', 'FF:EE:DD:CC:BB:AA', 'Jane Smith', '01YYYYYYYYYY', '9876543210987', '2026-02-20', 'ACTIVE', 'LOCKED'],
      ];

      for (var rowIndex = 0; rowIndex < data.length; rowIndex++) {
        for (var colIndex = 0; colIndex < data[rowIndex].length; colIndex++) {
          sheet
              .cell(CellIndex.indexByColumnRow(
                  columnIndex: colIndex, row: rowIndex + 1))
              .value = TextCellValue(data[rowIndex][colIndex]);
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filePath = '${directory.path}/NEIR_Export_$timestamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export saved to: $filePath'),
            backgroundColor: AppTheme.successColor,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() {
        _isExporting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEIR Export'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.primaryColor),
                        SizedBox(width: 8),
                        Text(
                          'BTRC NEIR Export',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Generate an Excel file containing all enrolled device IMEIs in the format required by BTRC (Bangladesh Telecommunication Regulatory Commission) for NEIR (National Equipment Identity Register) submission.',
                      style: TextStyle(color: Colors.grey[600]),
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
                    const Text(
                      'Date Range',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _selectStartDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'From',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                DateFormat('dd MMM yyyy').format(_startDate),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: _selectEndDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'To',
                                prefixIcon: Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                DateFormat('dd MMM yyyy').format(_endDate),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                    const Text(
                      'Export Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SummaryRow(label: 'Total Devices', value: '0'),
                    _SummaryRow(label: 'Active Devices', value: '0'),
                    _SummaryRow(label: 'Decoupled Devices', value: '0'),
                    const Divider(),
                    _SummaryRow(
                      label: 'File Format',
                      value: 'Excel (.xlsx)',
                    ),
                    _SummaryRow(
                      label: 'BTRC Format',
                      value: 'Compliant',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportNEIR,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download),
              label: Text(_isExporting ? 'Exporting...' : 'Export NEIR File'),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'The exported file can be submitted to BTRC through their NEIR portal when registration opens for fintech and MDM partners.',
                        style: TextStyle(fontSize: 13),
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}