import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/services/api_client.dart';
import '../../shared/models/device.dart';
import '../auth/auth_bloc.dart';

class DeviceDetailsScreen extends StatefulWidget {
  final String deviceId;

  const DeviceDetailsScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailsScreen> createState() => _DeviceDetailsScreenState();
}

class _DeviceDetailsScreenState extends State<DeviceDetailsScreen> {
  final ApiClient _apiClient = ApiClient();
  Device? _device;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/devices/${widget.deviceId}');
      if (response.statusCode == 200) {
        _device = Device.fromJson(response.data);
      }
    } catch (e) {
      _error = 'Failed to load device details';
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showLockRequestDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LockRequestSheet(device: _device!),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Details')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error ?? 'Device not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadDevice,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'location') {
                Navigator.pushNamed(context, '/gps-pull', arguments: _device!.id);
              } else if (value == 'message') {
                Navigator.pushNamed(context, '/custom-message', arguments: _device!.id);
              } else if (value == 'decouple') {
                Navigator.pushNamed(context, '/decouple', arguments: _device!.id);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'location',
                child: ListTile(
                  leading: Icon(Icons.location_on),
                  title: Text('Pull GPS Location'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'message',
                child: ListTile(
                  leading: Icon(Icons.message),
                  title: Text('Send Custom Message'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'decouple',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Request Decouple'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDevice,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildCustomerCard(),
              const SizedBox(height: 16),
              _buildDeviceCard(),
              const SizedBox(height: 16),
              _buildEMICard(),
              const SizedBox(height: 24),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _getStatusColor(_device!.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.phone_android,
                size: 32,
                color: _getStatusColor(_device!.status),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _device!.customerName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  _StatusChip(status: _device!.status),
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
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _infoRow('Phone', _device!.customerPhone),
            _infoRow('NID', _device!.customerNid),
            _infoRow(
              'Date of Birth',
              '${_device!.customerDob.year}-${_device!.customerDob.month.toString().padLeft(2, '0')}-${_device!.customerDob.day.toString().padLeft(2, '0')}',
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
            Text(
              'Device Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _infoRow('IMEI 1', _device!.imei1),
            if (_device!.imei2 != null) _infoRow('IMEI 2', _device!.imei2!),
            if (_device!.macAddress != null)
              _infoRow('MAC Address', _device!.macAddress!),
            _infoRow(
              'Enrollment Date',
              '${_device!.enrollmentDate.year}-${_device!.enrollmentDate.month.toString().padLeft(2, '0')}-${_device!.enrollmentDate.day.toString().padLeft(2, '0')}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEMICard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EMI Details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _infoRow('EMI Amount', '৳${_device!.emiAmount.toStringAsFixed(2)}'),
            _infoRow('Tenure', '${_device!.tenureMonths} months'),
            if (_device!.nextPaymentDate != null)
              _infoRow(
                'Next Payment',
                '${_device!.nextPaymentDate!.year}-${_device!.nextPaymentDate!.month.toString().padLeft(2, '0')}-${_device!.nextPaymentDate!.day.toString().padLeft(2, '0')}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_device!.status == DeviceStatus.active ||
            _device!.status == DeviceStatus.gracePeriod)
          ElevatedButton.icon(
            onPressed: _showLockRequestDialog,
            icon: const Icon(Icons.lock, color: Colors.white),
            label: const Text('Request Device Lock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        if (_device!.status == DeviceStatus.locked)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/unlock-request', arguments: _device!.id);
            },
            icon: const Icon(Icons.lock_open),
            label: const Text('Request Unlock'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showQrCode(),
          icon: const Icon(Icons.qr_code),
          label: const Text('Show Enrollment QR'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  void _showQrCode() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: _device!.id,
              version: QrVersions.auto,
              size: 200,
            ),
            const SizedBox(height: 16),
            Text(
              'Scan with customer device to link',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
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
      case DeviceStatus.decoupling:
        return AppTheme.primaryColor;
      case DeviceStatus.decoupled:
        return Colors.grey;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final DeviceStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          color: _getColor(),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.decoupling:
        return AppTheme.primaryColor;
      case DeviceStatus.decoupled:
        return Colors.grey;
    }
  }

  String _getLabel() {
    switch (status) {
      case DeviceStatus.active:
        return 'Active';
      case DeviceStatus.locked:
        return 'Locked';
      case DeviceStatus.gracePeriod:
        return 'Grace Period';
      case DeviceStatus.decoupling:
        return 'Decoupling';
      case DeviceStatus.decoupled:
        return 'Decoupled';
    }
  }
}

class LockRequestSheet extends StatefulWidget {
  final Device device;

  const LockRequestSheet({super.key, required this.device});

  @override
  State<LockRequestSheet> createState() => _LockRequestSheetState();
}

class _LockRequestSheetState extends State<LockRequestSheet> {
  final _noteController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submitRequest() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final apiClient = ApiClient();
      final authState = context.read<AuthBloc>().state;
      final response = await apiClient.post('/lock-requests', data: {
        'device_id': widget.device.id,
        'dealer_id': authState.user?.id,
        'reason_code': _selectedReason,
        'dealer_note': _noteController.text.trim(),
      });

      if (response.statusCode == 200) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lock request submitted for server verification'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit request: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 16),
          Text(
            'Request Device Lock',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Lock request will be verified by server based on EMI schedule.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          const Text(
            'Select Reason',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...LockReason.reasons.map((reason) => RadioListTile<String>(
                title: Text(reason.label),
                subtitle: Text(reason.description),
                value: reason.code,
                groupValue: _selectedReason,
                onChanged: (value) => setState(() => _selectedReason = value),
                contentPadding: EdgeInsets.zero,
              )),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            maxLength: 200,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Additional Note (Optional)',
              hintText: 'Max 200 characters',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Submit Lock Request'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

