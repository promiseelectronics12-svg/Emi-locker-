import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/firebase_service.dart';
import '../../auth/bloc/auth_bloc.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final Device device;

  const DeviceDetailsScreen({super.key, required this.device});

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  late Device _device;
  final FirebaseService _firebaseService = FirebaseService();
  final ApiClient _apiClient = ApiClient();

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _subscribeToUpdates();
  }

  void _subscribeToUpdates() {
    _firebaseService.deviceStatusStream.listen((data) {
      if (data['id'] == _device.id) {
        setState(() {
          _device = Device.fromJson(data);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDevice,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildCustomerCard(),
            const SizedBox(height: 16),
            _buildEmiCard(),
            const SizedBox(height: 16),
            _buildDeviceInfoCard(),
            const SizedBox(height: 16),
            _buildLocationCard(),
            const SizedBox(height: 24),
            if (_device.status == DeviceStatus.active ||
                _device.status == DeviceStatus.gracePeriod)
              _buildLockRequestButton(),
            if (_device.status == DeviceStatus.decoupling)
              _buildDecoupleButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: DeviceStatusColors.getColor(_device.status.name)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getStatusIcon(),
                color: DeviceStatusColors.getColor(_device.status.name),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _device.statusDisplayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: DeviceStatusColors.getColor(_device.status.name),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last sync: ${_device.lastSyncTime != null ? _formatLastSync() : "Never"}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (_device.status) {
      case DeviceStatus.active:
        return Icons.check_circle_outline;
      case DeviceStatus.locked:
        return Icons.lock_outline;
      case DeviceStatus.gracePeriod:
        return Icons.warning_amber_outlined;
      case DeviceStatus.decoupling:
        return Icons.sync;
      case DeviceStatus.decoupled:
        return Icons.power_settings_new;
      case DeviceStatus.blacklisted:
        return Icons.block;
    }
  }

  String _formatLastSync() {
    if (_device.lastSyncTime == null) return 'Never';
    final diff = DateTime.now().difference(_device.lastSyncTime!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM HH:mm').format(_device.lastSyncTime!);
  }

  Widget _buildCustomerCard() {
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
            const SizedBox(height: 16),
            _buildInfoRow(Icons.person_outline, 'Name', _device.customerName),
            _buildInfoRow(Icons.phone_outlined, 'Phone', _device.customerPhone),
            if (_device.customerNid != null)
              _buildInfoRow(Icons.badge_outlined, 'NID', _device.customerNid!),
            if (_device.isNidVerified)
              Row(
                children: [
                  const Icon(Icons.verified, size: 20, color: AppTheme.successColor),
                  const SizedBox(width: 8),
                  const Text(
                    'NID Verified',
                    style: TextStyle(color: AppTheme.successColor),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmiCard() {
    final progress = _device.paidAmount / _device.totalAmount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'EMI Progress',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${_device.paidMonths}/${_device.tenureMonths} months',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: AppTheme.dividerColor,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paid',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '৳${_device.paidAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Monthly EMI',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '৳${_device.monthlyEmi.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Outstanding',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '৳${_device.remainingAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_device.nextPaymentDate != null) ...[
              const Divider(height: 32),
              Row(
                children: [
                  Icon(
                    _device.isPaymentOverdue
                        ? Icons.warning_amber
                        : Icons.calendar_today,
                    size: 20,
                    color: _device.isPaymentOverdue
                        ? AppTheme.errorColor
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _device.isPaymentOverdue
                        ? 'Payment overdue since ${DateFormat('dd MMM yyyy').format(_device.nextPaymentDate!)}'
                        : 'Next payment: ${DateFormat('dd MMM yyyy').format(_device.nextPaymentDate!)}',
                    style: TextStyle(
                      color: _device.isPaymentOverdue
                          ? AppTheme.errorColor
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.phone_android, 'IMEI 1', _device.imei1),
            if (_device.imei2 != null)
              _buildInfoRow(Icons.phone_android, 'IMEI 2', _device.imei2!),
            if (_device.macAddress != null)
              _buildInfoRow(Icons.wifi, 'MAC Address', _device.macAddress!),
            if (_device.socInfo != null)
              _buildInfoRow(Icons.memory, 'SoC Info', _device.socInfo!),
            _buildInfoRow(
              Icons.calendar_today,
              'Enrolled',
              DateFormat('dd MMM yyyy').format(_device.enrollmentDate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_device.gpsLocation != null)
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _device.gpsLocation!,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              )
            else
              const Row(
                children: [
                  Icon(Icons.location_off, color: AppTheme.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    'Location not available',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLockRequestButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showLockRequestDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.errorColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: const Icon(Icons.lock_outline),
        label: const Text('Request Lock'),
      ),
    );
  }

  Widget _buildDecoupleButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showDecoupleDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: const Icon(Icons.sync),
        label: const Text('Push Decouple'),
      ),
    );
  }

  void _showLockRequestDialog() {
    LockReason? selectedReason;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request Lock'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select a reason:'),
                const SizedBox(height: 16),
                ...LockReason.values.map((reason) {
                  return RadioListTile<LockReason>(
                    title: Text(_getReasonDisplayName(reason)),
                    value: reason,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setDialogState(() => selectedReason = value);
                    },
                    contentPadding: EdgeInsets.zero,
                  );
                }),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional Note (optional)',
                    hintText: 'Max 200 characters',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _submitLockRequest(selectedReason!, noteController.text);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }

  String _getReasonDisplayName(LockReason reason) {
    switch (reason) {
      case LockReason.missedEmi:
        return 'Missed EMI';
      case LockReason.latePayment:
        return 'Late Payment';
      case LockReason.fraudSuspected:
        return 'Fraud Suspected';
      case LockReason.theftReported:
        return 'Theft Reported';
      case LockReason.customerRequest:
        return 'Customer Request';
      case LockReason.contractViolation:
        return 'Contract Violation';
      case LockReason.other:
        return 'Other';
    }
  }

  Future<void> _submitLockRequest(LockReason reason, String note) async {
    try {
      final authState = context.read<AuthBloc>().state;
      final userId =
          authState is AuthAuthenticated ? authState.user.id : '';

      final authenticated = await context.read<AuthBloc>().authenticateWithBiometrics();
      if (!authenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication required'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      final response = await _apiClient.post('/dealer/lock-request', data: {
        'device_id': _device.id,
        'dealer_id': userId,
        'reason': reason.name,
        'note': note.isNotEmpty ? note : null,
      });

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lock request submitted successfully'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        _refreshDevice();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.data['message'] ?? 'Failed to submit request'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit lock request'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _showDecoupleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Push Decouple'),
        content: const Text(
          'Are you sure you want to push decoupling for this device? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _pushDecouple();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _pushDecouple() async {
    try {
      final response = await _apiClient.post('/dealer/decouple', data: {
        'device_id': _device.id,
      });

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Decouple command sent'),
            backgroundColor: AppTheme.successColor,
          ),
        );
        _refreshDevice();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.data['message'] ?? 'Failed to send command'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to push decoupling'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _refreshDevice() async {
    try {
      final response = await _apiClient.get('/dealer/devices/${_device.id}');
      if (response.statusCode == 200) {
        setState(() {
          _device = Device.fromJson(response.data);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to refresh device'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }
}
