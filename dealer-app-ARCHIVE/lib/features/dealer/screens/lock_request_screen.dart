import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/models/device_model.dart';
import '../../shared/models/lock_request_model.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

class LockRequestScreen extends StatefulWidget {
  final DeviceModel device;

  const LockRequestScreen({super.key, required this.device});

  @override
  State<LockRequestScreen> createState() => _LockRequestScreenState();
}

class _LockRequestScreenState extends State<LockRequestScreen> {
  final ApiClient _apiClient = ApiClient();
  final _noteController = TextEditingController();

  LockReason? _selectedReason;
  bool _isSubmitting = false;
  bool _biometricPassed = false;

  final List<LockReason> _reasons = [
    LockReason.missedPayment,
    LockReason.fraudSuspected,
    LockReason.theft,
    LockReason.voluntary,
    LockReason.other,
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitLockRequest() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason')),
      );
      return;
    }

    if (!_biometricPassed) {
      final biometricAuth = BiometricAuthWidget(
        onSuccess: () {
          setState(() => _biometricPassed = true);
          _submitLockRequest();
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Authentication failed: $error'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        },
      );

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('2FA Required'),
          content: biometricAuth,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await _apiClient.post(
        '/devices/${widget.device.id}/lock-request',
        data: {
          'reason': _selectedReason!.name.toUpperCase(),
          'note': _noteController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lock request submitted for server verification'),
              backgroundColor: AppTheme.secondaryColor,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit lock request: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Lock'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceSummary(),
            const SizedBox(height: 24),
            _buildReasonSelector(),
            const SizedBox(height: 24),
            _buildNoteInput(),
            const SizedBox(height: 24),
            _buildServerVerificationInfo(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitLockRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Lock Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.person, size: 18),
                const SizedBox(width: 8),
                Text(widget.device.customerName),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone, size: 18),
                const SizedBox(width: 8),
                Text(widget.device.customerPhone),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Next Payment: ${widget.device.nextPaymentDate.day}/${widget.device.nextPaymentDate.month}/${widget.device.nextPaymentDate.year}',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.attach_money, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Remaining: ${widget.device.remainingAmount.toStringAsFixed(0)} BDT',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lock Reason',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...List.generate(_reasons.length, (index) {
          final reason = _reasons[index];
          final isSelected = _selectedReason == reason;
          return Card(
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              leading: Icon(
                _getReasonIcon(reason),
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(
                _getReasonLabel(reason),
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
              ),
              subtitle: Text(_getReasonDescription(reason)),
              trailing: isSelected
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                setState(() => _selectedReason = reason);
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNoteInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Additional Note (Optional)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Add any additional context for this lock request...',
          ),
        ),
      ],
    );
  }

  Widget _buildServerVerificationInfo() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Server Verification',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.blue.shade700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your lock request will be verified by the server against EMI schedule data. '
              'Requests with invalid reasons will be rejected. You cannot lock devices '
              'for non-payment reasons.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getReasonIcon(LockReason reason) {
    switch (reason) {
      case LockReason.missedPayment:
        return Icons.payment;
      case LockReason.fraudSuspected:
        return Icons.warning;
      case LockReason.theft:
        return Icons.phone_android;
      case LockReason.voluntary:
        return Icons.volunteer_activism;
      case LockReason.other:
        return Icons.more_horiz;
    }
  }

  String _getReasonLabel(LockReason reason) {
    switch (reason) {
      case LockReason.missedPayment:
        return 'Missed Payment';
      case LockReason.fraudSuspected:
        return 'Fraud Suspected';
      case LockReason.theft:
        return 'Theft Report';
      case LockReason.voluntary:
        return 'Voluntary Lock';
      case LockReason.other:
        return 'Other';
    }
  }

  String _getReasonDescription(LockReason reason) {
    switch (reason) {
      case LockReason.missedPayment:
        return 'Customer has missed scheduled payment';
      case LockReason.fraudSuspected:
        return 'Suspected fraudulent activity or identity';
      case LockReason.theft:
        return 'Device has been stolen';
      case LockReason.voluntary:
        return 'Customer requested temporary lock';
      case LockReason.other:
        return 'Other reason (specify in note)';
    }
  }
}