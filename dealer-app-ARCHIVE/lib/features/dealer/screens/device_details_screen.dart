import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/models/device_model.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import 'lock_request_screen.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailsScreen({super.key, required this.device});

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  final ApiClient _apiClient = ApiClient();
  DeviceModel? _device;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _loadDeviceDetails();
  }

  Future<void> _loadDeviceDetails() async {
    try {
      final response = await _apiClient.get('/devices/${_device!.id}');
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _device = DeviceModel.fromJson(response.data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeviceDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: 'Loading device details...')
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final device = _device!;
    final progress = device.paidAmount / device.totalAmount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(device),
          const SizedBox(height: 16),
          _buildCustomerCard(device),
          const SizedBox(height: 16),
          _buildPaymentCard(device, progress),
          const SizedBox(height: 16),
          if (device.customMessage != null) ...[
            _buildCustomMessageCard(device),
            const SizedBox(height: 16),
          ],
          _buildActionsCard(device),
        ],
      ),
    );
  }

  Widget _buildStatusCard(DeviceModel device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _getStatusIcon(device.status),
              size: 48,
              color: _getStatusColor(device.status),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.status.name.toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _getStatusColor(device.status),
                        ),
                  ),
                  if (device.currentLockMode != null)
                    Text(
                      'Lock Mode: ${device.currentLockMode}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            if (device.fraudFlags > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    Text(
                      '${device.fraudFlags}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(DeviceModel device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _infoRow(Icons.person, 'Name', device.customerName),
            _infoRow(Icons.phone, 'Phone', device.customerPhone),
            _infoRow(Icons.badge, 'NID', device.customerNid),
            _infoRow(
              Icons.calendar_today,
              'DOB',
              '${device.customerDob.day}/${device.customerDob.month}/${device.customerDob.year}',
            ),
            _infoRow(
              Icons.event,
              'Enrolled',
              '${device.enrollmentDate.day}/${device.enrollmentDate.month}/${device.enrollmentDate.year}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(DeviceModel device, double progress) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid: ${device.paidAmount.toStringAsFixed(0)} BDT',
                  style: const TextStyle(color: AppTheme.secondaryColor),
                ),
                Text(
                  'Total: ${device.totalAmount.toStringAsFixed(0)} BDT',
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                progress >= 1.0 ? AppTheme.secondaryColor : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Remaining: ${device.remainingAmount.toStringAsFixed(0)} BDT',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _infoRow(
              Icons.calendar_month,
              'Next Payment',
              '${device.nextPaymentDate.day}/${device.nextPaymentDate.month}/${device.nextPaymentDate.year}',
            ),
            _infoRow(
              Icons.access_time,
              'Monthly EMI',
              '${device.monthlyEmi.toStringAsFixed(0)} BDT',
            ),
            _infoRow(
              Icons.timer,
              'Tenure',
              '${device.tenureMonths} months (${device.paidMonths} paid)',
            ),
            if (device.lastPaymentDate != null)
              _infoRow(
                Icons.check_circle,
                'Last Payment',
                '${device.lastPaymentDate!.day}/${device.lastPaymentDate!.month}/${device.lastPaymentDate!.year}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomMessageCard(DeviceModel device) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.message, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom Message from Admin',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(device.customMessage!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(DeviceModel device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _navigateToLockRequest(device),
                icon: const Icon(Icons.lock),
                label: const Text('Request Lock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showDecoupleDialog(device),
                icon: const Icon(Icons.link_off),
                label: const Text('Request Decouple'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _flagFraud(device),
                icon: const Icon(Icons.flag),
                label: const Text('Flag Fraud'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return Icons.check_circle;
      case DeviceStatus.locked:
        return Icons.lock;
      case DeviceStatus.gracePeriod:
        return Icons.access_time;
      case DeviceStatus.decooupled:
        return Icons.link_off;
      case DeviceStatus.pendingEnrollment:
        return Icons.pending;
    }
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.secondaryColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.decooupled:
        return Colors.grey;
      case DeviceStatus.pendingEnrollment:
        return AppTheme.primaryColor;
    }
  }

  void _navigateToLockRequest(DeviceModel device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LockRequestScreen(device: device),
      ),
    ).then((_) => _loadDeviceDetails());
  }

  Future<void> _showDecoupleDialog(DeviceModel device) async {
    if (!device.isPaidOff) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device must be fully paid before decoupling'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request Decouple'),
        content: const Text(
          'This will notify the admin to decouple this device after payment verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiClient.post('/devices/${device.id}/request-decouple');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Decouple request submitted'),
              backgroundColor: AppTheme.secondaryColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit decouple request'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _flagFraud(DeviceModel device) async {
    final noteController = TextEditingController();

    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag Fraud'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'Reason for fraud flag',
            hintText: 'Describe the suspected fraud...',
          ),
          maxLines: 3,
          maxLength: 200,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, noteController.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    if (note != null && note.isNotEmpty) {
      try {
        await _apiClient.post('/devices/${device.id}/flag-fraud', data: {
          'note': note,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fraud flag submitted'),
              backgroundColor: AppTheme.secondaryColor,
            ),
          );
          _loadDeviceDetails();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit fraud flag'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }
}