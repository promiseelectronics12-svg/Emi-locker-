import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/device.dart';

class NeirExportPage extends StatefulWidget {
  const NeirExportPage({super.key});

  @override
  State<NeirExportPage> createState() => _NeirExportPageState();
}

class _NeirExportPageState extends State<NierExportPage> {
  final ApiClient _apiClient = ApiClient();

  List<Device> _devices = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/devices');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['devices'] as List<dynamic>;
        setState(() {
          _devices = data
              .map((json) => Device.fromJson(json as Map<String, dynamic>))
              .where((d) => !d.isDecoupled)
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['NEIR Export'];

      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('IMEI 1');
      sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('IMEI 2');
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('MAC Address');
      sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Customer Name');
      sheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Customer NID');
      sheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Customer Phone');
      sheet.cell(CellIndex.indexByString('G1')).value = TextCellValue('Enrollment Date');
      sheet.cell(CellIndex.indexByString('H1')).value = TextCellValue('Total Amount');
      sheet.cell(CellIndex.indexByString('I1')).value = TextCellValue('Paid Amount');
      sheet.cell(CellIndex.indexByString('J1')).value = TextCellValue('Status');
      sheet.cell(CellIndex.indexByString('K1')).value = TextCellValue('Export Date');

      int row = 2;
      for (final device in _devices) {
        sheet.cell(CellIndex.indexByString('A$row')).value =
            TextCellValue(device.imei1);
        sheet.cell(CellIndex.indexByString('B$row')).value =
            TextCellValue(device.imei2 ?? '');
        sheet.cell(CellIndex.indexByString('C$row')).value =
            TextCellValue(device.macAddress ?? '');
        sheet.cell(CellIndex.indexByString('D$row')).value =
            TextCellValue(device.customerName);
        sheet.cell(CellIndex.indexByString('E$row')).value =
            TextCellValue(device.customerNid);
        sheet.cell(CellIndex.indexByString('F$row')).value =
            TextCellValue(device.customerPhone);
        sheet.cell(CellIndex.indexByString('G$row')).value =
            TextCellValue(device.enrollmentDate.toString().split(' ')[0]);
        sheet.cell(CellIndex.indexByString('H$row')).value =
            DoubleCellValue(device.totalAmount);
        sheet.cell(CellIndex.indexByString('I$row')).value =
            DoubleCellValue(device.paidAmount);
        sheet.cell(CellIndex.indexByString('J$row')).value =
            TextCellValue(device.status.toString().split('.').last);
        sheet.cell(CellIndex.indexByString('K$row')).value =
            TextCellValue(_selectedDate.toString().split(' ')[0]);
        row++;
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/neir_export_$timestamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'NEIR Export - ${_selectedDate.toString().split(' ')[0]}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NEIR export generated successfully'),
            backgroundColor: AppTheme.successColor,
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
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
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
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDevices,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BTRC NEIR Export',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Generate Excel file with all enrolled device IMEIs in BTRC required format for submission.',
                                style: TextStyle(
                                  color: AppTheme.textSecondaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.folder_outlined,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Total Devices:'),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_devices.length}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('Export Date:'),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: _selectDate,
                                    child: Text(
                                      _selectedDate.toString().split(' ')[0],
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
                                'Preview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('IMEI')),
                                      DataColumn(label: Text('Customer')),
                                      DataColumn(label: Text('Status')),
                                    ],
                                    rows: _devices.take(10).map((device) {
                                      return DataRow(cells: [
                                        DataCell(Text(
                                          device.imei1,
                                          style: const TextStyle(fontSize: 12),
                                        )),
                                        DataCell(Text(
                                          device.customerName,
                                          style: const TextStyle(fontSize: 12),
                                        )),
                                        DataCell(Text(
                                          device.status
                                              .toString()
                                              .split('.')
                                              .last,
                                          style: const TextStyle(fontSize: 12),
                                        )),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ),
                              if (_devices.length > 10)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '... and ${_devices.length - 10} more devices',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondaryColor,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting ? null : _exportToExcel,
                          icon: _isExporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(
                            _isExporting
                                ? 'Generating...'
                                : 'Generate & Share Excel',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}