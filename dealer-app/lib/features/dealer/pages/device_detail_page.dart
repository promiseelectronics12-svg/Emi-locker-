import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/models/device.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/auth_service.dart';
import '../bloc/auth_bloc.dart';

class DeviceDetailPage extends StatefulWidget {
  final Device device;

  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  final ApiClient _apiClient = ApiClient();
  final AuthService _authService = AuthService();

  Device _device;
  bool _isLoading = false;

  DeviceDetailPage({required this.device}) : _device = device;

  Future<void> _submitLockRequest() async {
    if (!_validateBiometric()) return;

    final result = await showModalBottomSheet<LockReason>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const LockReasonSheet(),
    );

    if (result != null) {
      await _processLockRequest(result);
    }
  }

  bool _validateBiometric() {
    return true;
  }

  Future<void> _processLockRequest(LockReason reason) async {
    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.post('/devices/${_device.id}/lock-request', data: {
        'reason_code': _device.lockReasonString,
        'note': '',
      });

      if (response.statusCode == 200) {
        final verificationResult = response.data['verification_result'] as String;
        if (verificationResult == 'approved') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Lock request approved and device locked'),
                backgroundColor: AppTheme.successColor,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Request rejected: $verificationResult'),
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
        }
        _refreshDevice();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit lock request'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshDevice() async {
    try {
      final response = await _apiClient.get('/devices/${_device.id}');
      if (response.statusCode == 200) {
        setState(() {
          _device = Device.fromJson(response.data['device'] as Map<String, dynamic>);
        });
      }
    } catch (e) {
    }
  }

  void _showPaymentDialog() {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount (BDT)',
            prefixText: '৳ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _showCustomMessageDialog() {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Custom Message'),
        content: TextField(
          controller: messageController,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Message',
            hintText: 'Enter message to show on device (max 200 chars)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            _buildDeviceCard(),
            const SizedBox(height: 16),
            _buildPaymentCard(),
            const SizedBox(height: 24),
            _buildActionButtons(),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusColor(_device.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getStatusIcon(_device.status),
                color: _getStatusColor(_device.status),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getStatusText(_device.status),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_device.lockedAt != null)
                    Text(
                      'Locked on: ${_device.lockedAt!.toString().split('.')[0]}',
                      style: const TextStyle(
                        color: AppTheme.textSecondaryColor,
                        fontSize: 12,
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

  Widget _buildCustomerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.person_outline, 'Name', _device.customerName),
            _buildInfoRow(Icons.phone_outlined, 'Phone', _device.customerPhone),
            _buildInfoRow(Icons.badge_outlined, 'NID', _device.customerNid),
            _buildInfoRow(
              Icons.calendar_today_outlined,
              'Date of Birth',
              _device.customerDob.toString().split(' ')[0],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.memory_outlined, 'IMEI 1', _device.imei1),
            if (_device.imei2 != null)
              _buildInfoRow(Icons.memory_outlined, 'IMEI 2', _device.imei2!),
            if (_device.macAddress != null)
              _buildInfoRow(Icons.router_outlined, 'MAC', _device.macAddress!),
            _buildInfoRow(
              Icons.calendar_today_outlined,
              'Enrolled',
              _device.enrollmentDate.toString().split(' ')[0],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard() {
    final progress = _device.paymentProgress / 100;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '৳${_device.paidAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
                Text(
                  'of ৳${_device.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1 ? AppTheme.successColor : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_device.paymentProgress.toStringAsFixed(1)}% paid',
              style: const TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildPaymentInfo(
                    'Monthly EMI',
                    '৳${_device.emiAmount.toStringAsFixed(2)}',
                  ),
                ),
                Expanded(
                  child: _buildPaymentInfo(
                    'Next Payment',
                    _device.nextPaymentDate.toString().split(' ')[0],
                  ),
                ),
              ],
            ),
            if (_device.isPaymentOverdue) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_outlined,
                      color: AppTheme.errorColor,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Payment overdue!',
                        style: TextStyle(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _showPaymentDialog,
                      child: const Text('Record Payment'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondaryColor,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_device.status == DeviceStatus.active) ...[
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _submitLockRequest,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Request Lock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningColor,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: _showPaymentDialog,
          icon: const Icon(Icons.payment_outlined),
          label: const Text('Record Payment'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showCustomMessageDialog,
          icon: const Icon(Icons.message_outlined),
          label: const Text('Send Custom Message'),
        ),
        const SizedBox(height: 12),
        if (_device.status == DeviceStatus.pendingDecouple)
          OutlinedButton.icon(
            onPressed: () {
            },
            icon: const Icon(Icons.power_settings_new_outlined),
            label: const Text('Push Decouple'),
          ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.pendingDecouple:
        return Colors.orange;
      case DeviceStatus.decoupled:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return Icons.check_circle;
      case DeviceStatus.locked:
        return Icons.lock;
      case DeviceStatus.gracePeriod:
        return Icons.access_time;
      case DeviceStatus.pendingDecouple:
        return Icons.hourglass_empty;
      case DeviceStatus.decoupled:
        return Icons.power_settings_new;
    }
  }

  String _getStatusText(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return 'Active';
      case DeviceStatus.locked:
        return 'Locked';
      case DeviceStatus.gracePeriod:
        return 'Grace Period';
      case DeviceStatus.pendingDecouple:
        return 'Pending Decouple';
      case DeviceStatus.decoupled:
        return 'Decoupled';
    }
  }
}

class LockReasonSheet extends StatefulWidget {
  const LockReasonSheet({super.key});

  @override
  State<LockReasonSheet> createState() => _LockReasonSheetState();
}

class _LockReasonSheetState extends State<LockReasonSheet> {
  LockReason? _selectedReason;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Lock Reason',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...LockReason.values.map((reason) {
            return RadioListTile<LockReason>(
              value: reason,
              groupValue: _selectedReason,
              title: Text(_getReasonText(reason)),
              onChanged: (value) {
                setState(() => _selectedReason = value);
              },
            );
          }),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Additional details...',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedReason == null
                  ? null
                  : () {
                      Navigator.pop(context, _selectedReason);
                    },
              child: const Text('Submit Request'),
            ),
          ),
        ],
      ),
    );
  }

  String _getReasonText(LockReason reason) {
    switch (reason) {
      case LockReason.nonPayment:
        return 'Non-Payment';
      case LockReason.fraudulentActivity:
        return 'Fraudulent Activity';
      case LockReason.theft:
        return 'Theft';
      case LockReason.customerRequest:
        return 'Customer Request';
      case LockReason.other:
        return 'Other';
    }
  }
}