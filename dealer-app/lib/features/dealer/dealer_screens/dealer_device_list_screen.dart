import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/device_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class DealerDeviceListScreen extends StatefulWidget {
  final bool showLockAction;

  const DealerDeviceListScreen({
    super.key,
    this.showLockAction = false,
  });

  @override
  State<DealerDeviceListScreen> createState() => _DealerDeviceListScreenState();
}

class _DealerDeviceListScreenState extends State<DealerDeviceListScreen> {
  List<Device> _devices = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'ALL';

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
          queryParameters: {'dealer_id': authState.user!.id},
        );
        final data = response.data as Map<String, dynamic>;
        final devicesJson = data['devices'] as List<dynamic>;
        _devices = devicesJson
            .map((json) => Device.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load devices: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Device> get _filteredDevices {
    return _devices.where((device) {
      final matchesSearch = _searchQuery.isEmpty ||
          device.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          device.customerPhone.contains(_searchQuery) ||
          device.imei1.contains(_searchQuery);
      final matchesStatus = _statusFilter == 'ALL' ||
          device.status.name.toUpperCase() == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or IMEI',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isSelected: _statusFilter == 'ALL',
                  onTap: () => setState(() => _statusFilter = 'ALL'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Active',
                  isSelected: _statusFilter == 'ACTIVE',
                  onTap: () => setState(() => _statusFilter = 'ACTIVE'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Locked',
                  isSelected: _statusFilter == 'LOCKED',
                  onTap: () => setState(() => _statusFilter = 'LOCKED'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Grace',
                  isSelected: _statusFilter == 'GRACE_PERIOD',
                  onTap: () => setState(() => _statusFilter = 'GRACE_PERIOD'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Decoupled',
                  isSelected: _statusFilter == 'DECOUPLED',
                  onTap: () => setState(() => _statusFilter = 'DECOUPLED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDevices.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.phonelink_lock,
                        title: 'No devices found',
                        subtitle: 'Enroll your first device to get started',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDevices,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredDevices.length,
                          itemBuilder: (context, index) {
                            final device = _filteredDevices[index];
                            return DeviceCard(
                              deviceId: device.id,
                              customerName: device.customerName,
                              customerPhone: device.customerPhone,
                              status: device.status.name,
                              emiAmount: device.emiAmount,
                              progress: device.progressPercentage,
                              onTap: () => _showDeviceDetails(device),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showDeviceDetails(Device device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DeviceDetailsSheet(
        device: device,
        showLockAction: widget.showLockAction,
        onLockRequest: () => _showLockRequestDialog(device),
      ),
    );
  }

  void _showLockRequestDialog(Device device) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => _LockRequestDialog(device: device),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _DeviceDetailsSheet extends StatelessWidget {
  final Device device;
  final bool showLockAction;
  final VoidCallback onLockRequest;

  const _DeviceDetailsSheet({
    required this.device,
    required this.showLockAction,
    required this.onLockRequest,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.customerName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Validators.formatPhone(device.customerPhone),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: device.status.name),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Device Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              InfoRow(label: 'IMEI 1', value: device.imei1, copyable: true),
              InfoRow(label: 'IMEI 2', value: device.imei2.isNotEmpty ? device.imei2 : 'N/A', copyable: true),
              InfoRow(label: 'MAC Address', value: device.macAddress ?? 'N/A', copyable: true),
              InfoRow(
                label: 'Enrolled On',
                value: Validators.formatDate(device.enrollmentDate),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'EMI Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              InfoRow(
                label: 'Total Amount',
                value: Validators.formatCurrency(device.totalAmount),
              ),
              InfoRow(
                label: 'Paid Amount',
                value: Validators.formatCurrency(device.paidAmount),
              ),
              InfoRow(
                label: 'EMI Amount',
                value: Validators.formatCurrency(device.emiAmount),
              ),
              InfoRow(
                label: 'Remaining EMIs',
                value: '${device.remainingEmis} months',
              ),
              InfoRow(
                label: 'Next Payment',
                value: Validators.formatDate(device.nextPaymentDate),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: device.progressPercentage / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${device.progressPercentage.toStringAsFixed(1)}% paid off',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              if (device.status == DeviceStatus.active && showLockAction) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onLockRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                    ),
                    icon: const Icon(Icons.lock),
                    label: const Text('Request Device Lock'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _LockRequestDialog extends StatefulWidget {
  final Device device;

  const _LockRequestDialog({required this.device});

  @override
  State<_LockRequestDialog> createState() => _LockRequestDialogState();
}

class _LockRequestDialogState extends State<_LockRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  String _selectedReason = 'missed_payment';

  final List<Map<String, String>> _lockReasons = [
    {'code': 'missed_payment', 'label': 'Missed Payment', 'description': 'Customer has missed EMI payment'},
    {'code': 'fraudulent_activity', 'label': 'Fraudulent Activity', 'description': 'Suspicious or fraudulent behavior'},
    {'code': 'stolen', 'label': 'Stolen Device', 'description': 'Device reported stolen'},
    {'code': 'customer_request', 'label': 'Customer Request', 'description': 'Customer requests device lock'},
    {'code': 'terms_violation', 'label': 'Terms Violation', 'description': 'EMI terms and conditions violated'},
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitLockRequest() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      final apiClient = context.read<ApiClient>();
      await apiClient.post(
        '/lock-requests',
        data: {
          'device_id': widget.device.id,
          'dealer_id': widget.device.dealerId,
          'reason_code': _selectedReason,
          'dealer_note': _noteController.text.trim(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lock request submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit lock request: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request Device Lock'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a reason for the lock request:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ..._lockReasons.map((reason) {
                return RadioListTile<String>(
                  title: Text(reason['label']!),
                  subtitle: Text(
                    reason['description']!,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: reason['code']!,
                  groupValue: _selectedReason,
                  onChanged: (value) {
                    setState(() => _selectedReason = value!);
                  },
                  contentPadding: EdgeInsets.zero,
                );
              }),
              const SizedBox(height: 16),
              TextFormField(
                controller: _noteController,
                maxLength: 200,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional Note (Optional)',
                  hintText: 'Max 200 characters',
                  alignLabelWithHint: true,
                ),
                validator: Validators.validateLockNote,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The server will verify if this reason is valid based on EMI schedule data.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitLockRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.errorColor,
          ),
          child: const Text('Submit Request'),
        ),
      ],
    );
  }
}