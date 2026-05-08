import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/api/device_repository.dart';
import '../../../shared/api/lock_request_repository.dart';
import '../../../shared/models/device.dart';
import '../../../shared/models/lock_request.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';

class DeviceDashboardScreen extends StatefulWidget {
  const DeviceDashboardScreen({super.key});

  @override
  State<DeviceDashboardScreen> createState() => _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends State<DeviceDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _filterStatus = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'All Devices'),
            Tab(text: 'Lock Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDevicesTab(),
          _buildLockRequestsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/enroll-device');
        },
        icon: const Icon(Icons.add),
        label: const Text('Enroll'),
      ),
    );
  }

  Widget _buildDevicesTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL'),
                const SizedBox(width: 8),
                _buildFilterChip('ACTIVE'),
                const SizedBox(width: 8),
                _buildFilterChip('LOCKED'),
                const SizedBox(width: 8),
                _buildFilterChip('GRACE_PERIOD'),
                const SizedBox(width: 8),
                _buildFilterChip('DECOUPLING'),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Device>>(
            future: context.read<DeviceRepository>().getDevices(
                  status: _filterStatus == 'ALL' ? null : _filterStatus,
                ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return EmptyStateWidget(
                  icon: Icons.error_outline,
                  title: 'Failed to load devices',
                  subtitle: snapshot.error.toString(),
                  action: ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                );
              }

              final devices = snapshot.data ?? [];

              if (devices.isEmpty) {
                return EmptyStateWidget(
                  icon: Icons.phone_android,
                  title: 'No devices yet',
                  subtitle: 'Enroll your first device to get started',
                  action: ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/enroll-device');
                    },
                    child: const Text('Enroll Device'),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {});
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return DeviceCard(
                      device: device,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeviceDetailScreen(device: device),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String status) {
    final isSelected = _filterStatus == status;
    return FilterChip(
      label: Text(status.replaceAll('_', ' ')),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = status;
        });
      },
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
    );
  }

  Widget _buildLockRequestsTab() {
    return FutureBuilder<List<LockRequest>>(
      future: context.read<LockRequestRepository>().getLockRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return EmptyStateWidget(
            icon: Icons.error_outline,
            title: 'Failed to load lock requests',
            subtitle: snapshot.error.toString(),
          );
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.lock,
            title: 'No lock requests',
            subtitle: 'Lock request history will appear here',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: _getStatusIcon(request.status),
                  title: Text(request.reasonLabel),
                  subtitle: Text(
                    '${request.deviceId}\n${_formatDate(request.createdAt)}',
                  ),
                  isThreeLine: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(request.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      request.status,
                      style: TextStyle(
                        color: _getStatusColor(request.status),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return const Icon(Icons.hourglass_empty, color: AppTheme.warningColor);
      case 'APPROVED':
        return const Icon(Icons.check_circle, color: AppTheme.successColor);
      case 'REJECTED':
        return const Icon(Icons.cancel, color: AppTheme.errorColor);
      default:
        return const Icon(Icons.help_outline, color: Colors.grey);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return AppTheme.warningColor;
      case 'APPROVED':
        return AppTheme.successColor;
      case 'REJECTED':
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class DeviceDetailScreen extends StatelessWidget {
  final Device device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(device.customerName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Status'),
                        DeviceStatusBadge(status: device.status),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow('IMEI 1', device.imei1),
                    if (device.imei2.isNotEmpty)
                      _buildInfoRow('IMEI 2', device.imei2),
                    _buildInfoRow('Phone', device.customerPhone),
                    _buildInfoRow('NID', device.customerNid),
                    _buildInfoRow(
                      'DOB',
                      '${device.customerDob.day}/${device.customerDob.month}/${device.customerDob.year}',
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
                      'EMI Summary',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    _buildEmiRow(
                      'EMI Amount',
                      '${device.emiAmount.toStringAsFixed(0)} BDT',
                    ),
                    _buildEmiRow(
                      'Installments',
                      '${device.paidInstallments}/${device.totalInstallments}',
                    ),
                    _buildEmiRow(
                      'Paid Amount',
                      '${device.paidAmount.toStringAsFixed(0)} BDT',
                    ),
                    _buildEmiRow(
                      'Remaining',
                      '${device.remainingAmount.toStringAsFixed(0)} BDT',
                    ),
                    const Divider(height: 24),
                    _buildEmiRow(
                      'Next Payment',
                      _formatDate(device.nextPaymentDate),
                      isHighlighted: device.isPaymentOverdue,
                    ),
                    if (device.isPaymentOverdue)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: AppTheme.errorColor,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Payment overdue!',
                                style: TextStyle(
                                  color: AppTheme.errorColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (device.lockedAt != null) ...[
              Card(
                color: AppTheme.errorColor.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock,
                            color: AppTheme.errorColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lock Information',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTheme.errorColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Reason: ${device.lockReason ?? "N/A"}'),
                      Text(
                        'Since: ${_formatDate(device.lockedAt!)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (device.decoupleToken != null) ...[
              Card(
                color: AppTheme.warningColor.withOpacity(0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_off,
                            color: AppTheme.warningColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Decoupling Available',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTheme.warningColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Customer has made final payment. Decoupling can be initiated.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          _showDecoupleDialog(context);
                        },
                        icon: const Icon(Icons.link_off),
                        label: const Text('Initiate Decoupling'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (device.status == DeviceStatus.active) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LockRequestScreen(device: device),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                  ),
                  icon: const Icon(Icons.lock),
                  label: const Text('Request Lock'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondaryColor),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildEmiRow(String label, String value,
      {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondaryColor),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isHighlighted ? AppTheme.errorColor : null,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showDecoupleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initiate Decoupling'),
        content: const Text(
          'This will notify the system to decouple this device after final payment confirmation. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await context
                    .read<DeviceRepository>()
                    .requestDecouple(deviceId: device.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Decoupling initiated'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

class LockRequestScreen extends StatefulWidget {
  final Device device;

  const LockRequestScreen({super.key, required this.device});

  @override
  State<LockRequestScreen> createState() => _LockRequestScreenState();
}

class _LockRequestScreenState extends State<LockRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  LockReason? _selectedReason;
  bool _isLoading = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason')),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Confirm Lock Request',
        content:
            'This will submit a lock request to the server. The server will verify if the reason is valid based on EMI schedule data.',
        confirmText: 'Submit Request',
        confirmColor: AppTheme.errorColor,
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final lockRepo = context.read<LockRequestRepository>();
      await lockRepo.submitLockRequest(
        deviceId: widget.device.id,
        reasonCode: _selectedReason!.code,
        dealerNote: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lock request submitted successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Lock'),
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Device Information',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('Customer: ${widget.device.customerName}'),
                        Text('Phone: ${widget.device.customerPhone}'),
                        Text('IMEI: ${widget.device.imei1}'),
                        const Divider(height: 24),
                        Text(
                          'EMI Status: ${widget.device.paidInstallments}/${widget.device.totalInstallments} paid',
                        ),
                        if (widget.device.isPaymentOverdue)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Payment is overdue',
                              style: TextStyle(color: AppTheme.errorColor),
                            ),
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
                          'Lock Reason',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ...LockReason.predefinedReasons.map((reason) {
                          return RadioListTile<LockReason>(
                            title: Text(reason.label),
                            subtitle: Text(reason.description),
                            value: reason,
                            groupValue: _selectedReason,
                            onChanged: (value) {
                              setState(() {
                                _selectedReason = value;
                              });
                            },
                          );
                        }),
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
                          'Additional Note (Optional)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _noteController,
                          maxLength: 200,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Add any additional details...',
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
                    onPressed: _isLoading ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.lock),
                    label: const Text('Submit Lock Request'),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lock requests are verified by the server against EMI schedule data. Invalid requests will be rejected.',
                          style: TextStyle(
                            color: AppTheme.primaryColor,
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
      ),
    );
  }
}