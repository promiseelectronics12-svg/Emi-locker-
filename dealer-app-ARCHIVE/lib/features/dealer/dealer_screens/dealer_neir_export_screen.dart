import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../shared/api/api_client.dart';
import '../../shared/models/device_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class DealerNierExportScreen extends StatefulWidget {
  const DealerNierExportScreen({super.key});

  @override
  State<DealerNierExportScreen> createState() => _DealerNierExportScreenState();
}

class _DealerNierExportScreenState extends State<DealerNierExportScreen> {
  List<Device> _devices = [];
  bool _isLoading = true;
  bool _isExporting = false;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 365));
  DateTime _endDate = DateTime.now();
  int _selectedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/devices',
          queryParameters: {
            'dealer_id': authState.user!.id,
            'enrolled_after': _startDate.toIso8601String(),
            'enrolled_before': _endDate.toIso8601String(),
          },
        );
        final data = response.data as Map<String, dynamic>;
        final devicesJson = data['devices'] as List<dynamic>;
        setState(() {
          _devices = devicesJson
              .map((json) => Device.fromJson(json as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load devices: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToExcel() async {
    setState(() => _isExporting = true);

    try {
      final excel = Excel.createExcel();
      final sheet = excel['NEIR_Export'];

      sheet.appendRow([
        TextCellValue('SL No'),
        TextCellValue('IMEI 1'),
        TextCellValue('IMEI 2'),
        TextCellValue('Customer Name'),
        TextCellValue('Customer Phone'),
        TextCellValue('Customer NID'),
        TextCellValue('Enrollment Date'),
        TextCellValue('Device Status'),
        TextCellValue('Total EMI Amount'),
        TextCellValue('EMI Tenure'),
      ]);

      for (var i = 0; i < _devices.length; i++) {
        final device = _devices[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(device.imei1),
          TextCellValue(device.imei2),
          TextCellValue(device.customerName),
          TextCellValue(device.customerPhone),
          TextCellValue(device.customerNid),
          TextCellValue(Validators.formatDate(device.enrollmentDate)),
          TextCellValue(device.status.name.toUpperCase()),
          DoubleCellValue(device.totalAmount),
          IntCellValue(device.emiTenure),
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/NEIR_Export_$timestamp.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(excel.encode()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEIR Export'),
        actions: [
          if (_devices.isNotEmpty)
            TextButton.icon(
              onPressed: _isExporting ? null : _exportToExcel,
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text(
                'Export',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
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
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Generate Excel file with all enrolled device IMEIs in BTRC\'s required format for submission.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _DateSelector(
                        label: 'From',
                        date: _startDate,
                        onTap: () => _selectDate(true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DateSelector(
                        label: 'To',
                        date: _endDate,
                        onTap: () => _selectDate(false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '${_devices.length} devices found',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadDevices,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _devices.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.folder_open,
                        title: 'No devices found',
                        subtitle: 'No devices enrolled in the selected date range',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final device = _devices[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.phonelink_lock,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                              title: Text(
                                device.customerName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'IMEI: ${device.imei1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: StatusBadge(status: device.status.name),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
        } else {
          _endDate = date;
        }
      });
      _loadDevices();
    }
  }
}

class _DateSelector extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateSelector({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  Validators.formatDate(date),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}