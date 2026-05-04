import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:excel/excel.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/models/analytics.dart';
import 'bloc/neir_export_bloc.dart';

class NeirExportScreen extends StatefulWidget {
  const NeirExportScreen({super.key});

  @override
  State<NeirExportScreen> createState() => _NeirExportScreenState();
}

class _NeirExportScreenState extends State<NeirExportScreen> {
  final Set<String> _selectedIds = {};
  List<NeirDeviceRecord> _devices = [];

  @override
  void initState() {
    super.initState();
    context.read<NeirExportBloc>().add(LoadNeirDevices());
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _devices.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_devices.map((d) => d.imei));
      }
    });
  }

  Future<void> _exportForBtrc() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one device'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    final selectedDevices = _devices.where((d) => _selectedIds.contains(d.imei)).toList();

    try {
      final file = await _generateBtrcExcel(selectedDevices);
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'NEIR Export - $timestamp - EMI Locker Platform',
        subject: 'NEIR Export for BTRC',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${selectedDevices.length} devices for BTRC NEIR'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
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

  Future<File> _generateBtrcExcel(List<NeirDeviceRecord> devices) async {
    final excel = Excel.createExcel();
    final sheet = excel['NEIR_Export'];

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: HorizontalAlign.left,
      backgroundColor: HexColor('1F4E79'),
      fontColor: 'FFFFFF',
    );

    final headers = [
      'IMEI',
      'Device Brand',
      'Model',
      'Dealer NID',
      'Dealer Business Name',
      'Registration Date',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    final dateFormat = DateFormat('yyyy-MM-dd');

    for (var rowIndex = 0; rowIndex < devices.length; rowIndex++) {
      final record = devices[rowIndex];
      final dataRow = [
        TextCellValue(record.imei),
        TextCellValue(record.deviceModel),
        TextCellValue(record.deviceModel),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(dateFormat.format(DateTime.now())),
      ];

      for (var colIndex = 0; colIndex < dataRow.length; colIndex++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1));
        cell.value = dataRow[colIndex];
      }
    }

    for (var colIndex = 0; colIndex < headers.length; colIndex++) {
      sheet.setColumnWidth(colIndex, 25);
    }

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'NEIR_Export_$timestamp.xlsx';
    final file = File('${directory.path}/$fileName');

    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Failed to encode Excel file');
    }

    await file.writeAsBytes(fileBytes);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEIR Export'),
        actions: [
          TextButton.icon(
            onPressed: _selectAll,
            icon: const Icon(Icons.select_all, color: Colors.white),
            label: Text(
              _selectedIds.length == _devices.length ? 'Deselect All' : 'Select All',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BTRC NEIR Format',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Export device IMEIs in the official BTRC NEIR format for submission',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: BlocConsumer<NeirExportBloc, NeirExportState>(
              listener: (context, state) {
                if (state is NeirDevicesLoaded) {
                  _devices = state.devices;
                }
                if (state is NeirExportError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is NeirExportLoading) {
                  return const LoadingIndicator(message: 'Loading devices...');
                }
                if (_devices.isEmpty) {
                  return const EmptyState(
                    icon: Icons.file_download_outlined,
                    title: 'No Devices',
                    subtitle: 'No devices available for NEIR export',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isSelected = _selectedIds.contains(device.imei);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) => _toggleSelection(device.imei),
                        title: Text(device.customerName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IMEI: ${device.imei}'),
                            Text(
                              'EMI: ৳${device.emiAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: isSelected
                              ? AppTheme.successColor
                              : AppTheme.textSecondaryColor.withOpacity(0.2),
                          child: Icon(
                            isSelected ? Icons.check : Icons.phone_android,
                            color: isSelected ? Colors.white : AppTheme.textSecondaryColor,
                            size: 20,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _selectedIds.isEmpty ? null : _exportForBtrc,
                  icon: const Icon(Icons.file_download, color: Colors.white),
                  label: Text(
                    'Export for BTRC NEIR (${_selectedIds.length} devices)',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.dealerColor,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email, color: AppTheme.warningColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Email this file to neir@btrc.gov.bd',
                          style: TextStyle(
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
