import 'package:flutter/material.dart';
import '../../../../../shared/models/device_model.dart';

class DeviceListTile extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const DeviceListTile({
    super.key,
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(device.status),
          radius: 24,
          child: const Icon(Icons.phone_android, color: Colors.white),
        ),
        title: Text(
          device.customerName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'IMEI: ${device.imei1}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            Text(
              '${device.emiAmount.toStringAsFixed(0)} BDT/month',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStatusBadge(device.status),
            const SizedBox(height: 4),
            if (device.isPaymentOverdue)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'OVERDUE',
                  style: TextStyle(
                    color: Colors.red[800],
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DeviceStatus status) {
    String label;
    Color color;

    switch (status) {
      case DeviceStatus.active:
        label = 'Active';
        color = Colors.green;
        break;
      case DeviceStatus.reminder:
        label = 'Reminder';
        color = Colors.blue;
        break;
      case DeviceStatus.partialLock:
        label = 'Partial Lock';
        color = Colors.orange;
        break;
      case DeviceStatus.fullLock:
        label = 'Full Lock';
        color = Colors.red;
        break;
      case DeviceStatus.paidOff:
        label = 'Paid Off';
        color = Colors.grey;
        break;
      case DeviceStatus.compromised:
        label = 'Compromised';
        color = Colors.purple;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return Colors.green;
      case DeviceStatus.reminder:
        return Colors.blue;
      case DeviceStatus.partialLock:
        return Colors.orange;
      case DeviceStatus.fullLock:
        return Colors.red;
      case DeviceStatus.paidOff:
        return Colors.grey;
      case DeviceStatus.compromised:
        return Colors.purple;
    }
  }
}