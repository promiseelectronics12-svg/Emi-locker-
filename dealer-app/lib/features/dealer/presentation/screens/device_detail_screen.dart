import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/models/device_model.dart';

class DeviceDetailScreen extends StatelessWidget {
  final Device device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        backgroundColor: AppTheme.dealerColor,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'lock':
                  Navigator.pushNamed(
                    context,
                    '/dealer/lock-request',
                    arguments: device,
                  );
                  break;
                case 'location':
                  break;
                case 'message':
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'lock',
                child: ListTile(
                  leading: Icon(Icons.lock),
                  title: Text('Request Lock'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'location',
                child: ListTile(
                  leading: Icon(Icons.location_on),
                  title: Text('Get Location'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'message',
                child: ListTile(
                  leading: Icon(Icons.message),
                  title: Text('Send Message'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildCustomerInfo(),
            _buildEMIInfo(),
            _buildDeviceInfo(),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: _getStatusColor(device.status).withOpacity(0.1),
      child: Column(
        children: [
          Icon(
            _getStatusIcon(),
            size: 64,
            color: _getStatusColor(device.status),
          ),
          const SizedBox(height: 12),
          Text(
            device.customerName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            device.customerPhone,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(device.status),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              device.status,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Customer Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Name', value: device.customerName),
            _InfoRow(label: 'Phone', value: device.customerPhone),
            _InfoRow(label: 'NID', value: device.customerNid),
            _InfoRow(
              label: 'Date of Birth',
              value: _formatDate(device.customerDob),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEMIInfo() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EMI Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: 'EMI Amount',
              value: device.emiAmount != null ? '৳${device.emiAmount!.toStringAsFixed(0)}' : 'N/A',
            ),
            _InfoRow(
              label: 'Installments Paid',
              value: '${device.installmentsPaid ?? 0} / ${device.totalInstallments ?? 0}',
            ),
            _InfoRow(
              label: 'Next Payment',
              value: device.nextPaymentDate != null
                  ? _formatDate(device.nextPaymentDate!)
                  : 'N/A',
            ),
            if (device.enrollmentDate != null)
              _InfoRow(
                label: 'Enrollment Date',
                value: _formatDate(device.enrollmentDate!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Device ID', value: device.id),
            _InfoRow(label: 'IMEI 1', value: device.imei1),
            if (device.imei2 != null)
              _InfoRow(label: 'IMEI 2', value: device.imei2!),
            if (device.macAddress != null)
              _InfoRow(label: 'MAC Address', value: device.macAddress!),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                '/dealer/lock-request',
                arguments: device,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.lock),
            label: const Text('Request Lock'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.location_on),
                  label: const Text('Get Location'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.message),
                  label: const Text('Send Message'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.history),
            label: const Text('View Payment History'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return AppTheme.successColor;
      case 'LOCKED':
        return AppTheme.errorColor;
      case 'OVERDUE':
        return AppTheme.warningColor;
      case 'DECOUPLED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (device.status.toUpperCase()) {
      case 'ACTIVE':
        return Icons.check_circle;
      case 'LOCKED':
        return Icons.lock;
      case 'OVERDUE':
        return Icons.warning;
      case 'DECOUPLED':
        return Icons.link_off;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}