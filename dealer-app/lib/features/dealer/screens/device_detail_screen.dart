import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/api/api_client.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/constants.dart';
import '../../auth/bloc/auth_bloc.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final _noteController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitLockRequest() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a lock reason')),
      );
      return;
    }

    final authenticated = await _authenticateBiometric();
    if (!authenticated) return;

    if (!mounted) return;

    setState(() => _isSubmitting = true);

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.createLockRequest({
        'device_id': widget.device.id,
        'reason_code': _selectedReason,
        'dealer_note': _noteController.text.isNotEmpty ? _noteController.text : null,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lock request submitted successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${_extractError(e)}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _authenticateBiometric() async {
    final localAuth = LocalAuthentication();

    try {
      final canAuth = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
      if (!canAuth) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication not available')),
        );
        return false;
      }

      final didAuth = await localAuth.authenticate(
        localizedReason: 'Authenticate to submit lock request',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      return didAuth;
    } catch (e) {
      return false;
    }
  }

  String _extractError(dynamic e) {
    final str = e.toString();
    if (str.contains('401')) return 'Session expired';
    if (str.contains('network')) return 'Network error';
    return 'Submission failed';
  }

  void _showLockRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Submit Lock Request',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Server will verify if reason is valid based on EMI schedule data.',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Reason',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...AppConstants.lockReasons.map((reason) => RadioListTile<String>(
                  title: Text(AppConstants.lockReasonLabels[reason] ?? reason),
                  value: reason,
                  groupValue: _selectedReason,
                  onChanged: (v) => setState(() => _selectedReason = v),
                  contentPadding: EdgeInsets.zero,
                )),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              maxLength: AppConstants.maxNoteLength,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Additional details...',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Server verification is required. Invalid requests will be rejected.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitLockRequest,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppTheme.errorColor,
              ),
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit Lock Request', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
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
            _buildDeviceCard(),
            const SizedBox(height: 24),
            if (widget.device.status != DeviceStatus.decoupled &&
                widget.device.status != DeviceStatus.locked)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showLockRequestDialog,
                  icon: const Icon(Icons.lock),
                  label: const Text('Request Lock'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.errorColor,
                  ),
                ),
              ),
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
                color: _getStatusColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.info_outline, color: _getStatusColor(), size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(),
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

  Color _getStatusColor() {
    switch (widget.device.status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.decoupled:
        return Colors.grey;
      case DeviceStatus.pendingDecouple:
        return Colors.blue;
    }
  }

  String _getStatusText() {
    switch (widget.device.status) {
      case DeviceStatus.active:
        return 'Active';
      case DeviceStatus.locked:
        return 'Locked';
      case DeviceStatus.gracePeriod:
        return 'Grace Period';
      case DeviceStatus.decoupled:
        return 'Decoupled';
      case DeviceStatus.pendingDecouple:
        return 'Pending Decouple';
    }
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            _buildInfoRow('Name', widget.device.customerName),
            _buildInfoRow('Phone', widget.device.customerPhone),
            _buildInfoRow('NID', widget.device.customerNid),
            _buildInfoRow('DOB', widget.device.customerDob.toString().split(' ')[0]),
          ],
        ),
      ),
    );
  }

  Widget _buildEmiCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EMI Information',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            _buildInfoRow('EMI Amount', 'BDT ${widget.device.emiAmount.toStringAsFixed(0)}/month'),
            _buildInfoRow('Tenure', '${widget.device.tenureMonths} months'),
            _buildInfoRow('Paid', '${widget.device.paidMonths} months'),
            _buildInfoRow('Remaining', 'BDT ${widget.device.remainingAmount.toStringAsFixed(0)}'),
            _buildInfoRow('Next Payment', widget.device.nextPaymentDate.toString().split(' ')[0]),
            if (widget.device.isPaymentOverdue)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.device.overdueDays} days overdue',
                  style: const TextStyle(color: AppTheme.warningColor, fontWeight: FontWeight.w500),
                ),
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            _buildInfoRow('IMEI 1', widget.device.imei1),
            if (widget.device.imei2.isNotEmpty) _buildInfoRow('IMEI 2', widget.device.imei2),
            if (widget.device.macAddress.isNotEmpty) _buildInfoRow('MAC', widget.device.macAddress),
            _buildInfoRow('Enrolled', widget.device.enrolledAt.toString().split(' ')[0]),
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
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}