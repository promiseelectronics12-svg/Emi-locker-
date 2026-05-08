import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/constants/constants.dart';
import '../bloc/dealer_bloc.dart';

class NEIRExportScreen extends StatefulWidget {
  const NEIRExportScreen({super.key});

  @override
  State<NEIRExportScreen> createState() => _NEIRExportScreenState();
}

class _NEIRExportScreenState extends State<NEIRExportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  void _loadDevices() {
    context.read<DealerBloc>().add(
          LoadDevices(
            page: 1,
            limit: 1000,
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
    }
  }

  Future<void> _exportNEIR() async {
    setState(() => _isExporting = true);

    try {
      final state = context.read<DealerBloc>().state;
      final devices = state.devices;

      final excel = Excel.createExcel();
      final sheet = excel['NEIR Export'];

      sheet.appendRow([
        TextCellValue('IMEI 1'),
        TextCellValue('IMEI 2'),
        TextCellValue('MAC Address'),
        TextCellValue('Customer Name'),
        TextCellValue('Customer Phone'),
        TextCellValue('Customer NID'),
        TextCellValue('Enrollment Date'),
        TextCellValue('Total Amount'),
        TextCellValue('Status'),
      ]);

      for (final device in devices) {
        final enrolledDate = device.enrolledAt != null
            ? DateFormat('yyyy-MM-dd').format(device.enrolledAt!)
            : '';

        sheet.appendRow([
          TextCellValue(device.imei1),
          TextCellValue(device.imei2 ?? ''),
          TextCellValue(device.macAddress),
          TextCellValue(device.customerName),
          TextCellValue(device.customerPhone),
          TextCellValue(device.customerNid),
          TextCellValue(enrolledDate),
          TextCellValue(device.totalAmount.toString()),
          TextCellValue(device.status),
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'NEIR_Export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'NEIR Export - ${DateFormat('dd MMM yyyy').format(_startDate)} to ${DateFormat('dd MMM yyyy').format(_endDate)}',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported ${devices.length} devices'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
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
      setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEIR Export'),
      ),
      body: BlocBuilder<DealerBloc, DealerState>(
        builder: (context, state) {
          return Padding(
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
                        Text(
                          'Export Period',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(true),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Start Date',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('dd MMM yyyy').format(_startDate),
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () => _selectDate(false),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'End Date',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('dd MMM yyyy').format(_endDate),
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                    ],
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
                        Text(
                          'Export Summary',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        _SummaryRow(
                          label: 'Total Devices',
                          value: state.devices.length.toString(),
                        ),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          label: 'Active Devices',
                          value: state.devices
                              .where((d) => d.status == 'ACTIVE')
                              .length
                              .toString(),
                        ),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          label: 'Decoupled Devices',
                          value: state.devices
                              .where((d) => d.status == 'DECOUPLED')
                              .length
                              .toString(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.primaryColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This export generates an Excel file with all enrolled device IMEIs in BTRC\'s required format.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isExporting ? null : _exportNEIR,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download),
                  label: Text(_isExporting ? 'Exporting...' : 'Export to Excel'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
          );
        },
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

class LockRequestsScreen extends StatefulWidget {
  const LockRequestsScreen({super.key});

  @override
  State<LockRequestsScreen> createState() => _LockRequestsScreenState();
}

class _LockRequestsScreenState extends State<LockRequestsScreen> {
  List<LockRequest> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLockRequests();
  }

  Future<void> _loadLockRequests() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get(
        ApiConstants.lockRequestEndpoint,
        queryParameters: {'status': 'PENDING'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['requests'] ?? [];
        setState(() {
          _requests = data.map((r) => LockRequest.fromJson(r)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load lock requests: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lock Requests'),
      ),
      body: _isLoading
          ? const LoadingWidget(message: 'Loading lock requests...')
          : _requests.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.lock,
                  title: 'No Lock Requests',
                  subtitle: 'All device lock requests will appear here',
                )
              : RefreshIndicator(
                  onRefresh: _loadLockRequests,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (context, index) {
                      final request = _requests[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lock, color: AppTheme.warningColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    request.reasonLabel,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const Spacer(),
                                  StatusBadge(status: request.status),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Device: ${request.deviceId}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (request.note != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Note: ${request.note}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'Requested: ${DateFormat('dd MMM yyyy HH:mm').format(request.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}