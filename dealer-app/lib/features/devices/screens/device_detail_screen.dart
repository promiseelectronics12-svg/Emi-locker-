import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/models/device.dart';
import '../bloc/device_bloc.dart';
import '../bloc/device_state.dart';
import '../widgets/lock_request_sheet.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final _dateFormat = DateFormat('MMM dd, yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceBloc, DeviceState>(
      builder: (context, state) {
        final device = state.devices.firstWhere(
          (d) => d.id == widget.deviceId,
          orElse: () => throw Exception('Device not found'),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(device.model),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusHeader(device),
                const SizedBox(height: 16),
                _buildActionButtons(context, device),
                const SizedBox(height: 24),
                _buildSectionTitle('Customer Info'),
                _buildCustomerCard(device),
                const SizedBox(height: 24),
                _buildSectionTitle('Device Info'),
                _buildDeviceInfoCard(device),
                const SizedBox(height: 24),
                _buildSectionTitle('Location'),
                _buildLocationCard(device),
                const SizedBox(height: 24),
                _buildSectionTitle('EMI Schedule'),
                _buildEmiScheduleCard(device),
                const SizedBox(height: 24),
                _buildSectionTitle('Payment History'),
                _buildPaymentHistoryCard(device),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusColor(device.status).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.security,
                color: _getStatusColor(device.status),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getStatusLabel(device.status),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(device.status),
                    ),
                  ),
                  if (device.lastStateChangeAt != null)
                    Text(
                      'Last updated: ${_dateFormat.format(device.lastStateChangeAt!)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Device device) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(
          label: 'Request Lock',
          icon: Icons.lock,
          color: AppTheme.errorColor,
          onPressed: () => _showLockRequest(context, device),
        ),
        _ActionButton(
          label: 'Request Unlock',
          icon: Icons.lock_open,
          color: AppTheme.successColor,
          onPressed: () {},
        ),
        _ActionButton(
          label: 'Grant Grace',
          icon: Icons.timer,
          color: AppTheme.warningColor,
          onPressed: () {},
        ),
        _ActionButton(
          label: 'Send Message',
          icon: Icons.message,
          color: AppTheme.primaryColor,
          onPressed: () {},
        ),
        _ActionButton(
          label: 'Pull Location',
          icon: Icons.gps_fixed,
          color: Colors.blueGrey,
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCustomerCard(Device device) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Name'),
            subtitle: Text(device.customerName),
            leading: const Icon(Icons.person),
          ),
          ListTile(
            title: const Text('Phone'),
            subtitle: Text(device.customerPhone),
            leading: const Icon(Icons.phone),
            trailing: IconButton(
              icon: const Icon(Icons.call, color: AppTheme.primaryColor),
              onPressed: () => launchUrl(Uri.parse('tel:${device.customerPhone}')),
            ),
          ),
          ListTile(
            title: const Text('NID'),
            subtitle: Text(device.customerNid),
            leading: const Icon(Icons.badge),
          ),
          if (device.customerNidPhotoUrl != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                onTap: () => _viewPhoto(device.customerNidPhotoUrl!),
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(device.customerNidPhotoUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    alignment: Alignment.bottomRight,
                    padding: const EdgeInsets.all(8),
                    child: const CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.fullscreen, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            _InfoRow(label: 'IMEI 1', value: device.imei1),
            _InfoRow(label: 'IMEI 2', value: device.imei2),
            _InfoRow(label: 'Serial', value: device.serial),
            _InfoRow(label: 'OEM', value: device.oem),
            _InfoRow(label: 'Model', value: device.model),
            _InfoRow(label: 'Android Version', value: device.androidVersion),
            _InfoRow(label: 'Enrollment Date', value: DateFormat('MMM dd, yyyy').format(device.enrolledAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(Device device) {
    if (device.lastLocation == null) {
      return const Card(
        child: ListTile(
          title: Text('No location data available'),
          leading: Icon(Icons.location_off),
        ),
      );
    }

    final lat = device.lastLocation!['lat'];
    final lng = device.lastLocation!['lng'];
    final timestamp = device.lastLocation!['timestamp'] != null 
        ? DateTime.parse(device.lastLocation!['timestamp'])
        : null;

    return Card(
      child: ListTile(
        title: Text('Last known: $lat, $lng'),
        subtitle: timestamp != null ? Text('Updated: ${_dateFormat.format(timestamp)}') : null,
        leading: const Icon(Icons.location_on, color: Colors.red),
        trailing: const Icon(Icons.map, color: AppTheme.primaryColor),
        onTap: () => _openMap(lat, lng),
      ),
    );
  }

  Widget _buildEmiScheduleCard(Device device) {
    if (device.emiSchedule == null || device.emiSchedule!.isEmpty) {
      return const Card(child: ListTile(title: Text('No EMI schedule available')));
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: device.emiSchedule!.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = device.emiSchedule![index];
          return ListTile(
            dense: true,
            title: Text('Installment #${item.installmentNumber}'),
            subtitle: Text('Due: ${DateFormat('MMM dd, yyyy').format(item.dueDate)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '৳${item.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Icon(
                  item.isPaid ? Icons.check_circle : Icons.pending,
                  color: item.isPaid ? Colors.green : Colors.orange,
                  size: 20,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentHistoryCard(Device device) {
    if (device.paymentHistory == null || device.paymentHistory!.isEmpty) {
      return const Card(child: ListTile(title: Text('No payment history recorded')));
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: device.paymentHistory!.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final payment = device.paymentHistory![index];
          return ListTile(
            dense: true,
            title: Text('৳${payment.amount.toStringAsFixed(0)} via ${payment.paymentMethod}'),
            subtitle: Text(DateFormat('MMM dd, yyyy HH:mm').format(payment.paymentDate)),
            trailing: const Icon(Icons.receipt_long, size: 20, color: Colors.grey),
          );
        },
      ),
    );
  }

  void _showLockRequest(BuildContext context, Device device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LockRequestSheet(device: device),
    );
  }

  void _viewPhoto(String url) {
    // Implement photo viewer or launch browser
    launchUrl(Uri.parse(url));
  }

  void _openMap(double lat, double lng) async {
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    }
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active: return AppTheme.successColor;
      case DeviceStatus.reminder: return AppTheme.warningColor;
      case DeviceStatus.partialLock: return Colors.orange;
      case DeviceStatus.fullLock: return AppTheme.errorColor;
      case DeviceStatus.paidOff: return Colors.blue;
      case DeviceStatus.compromised: return Colors.purple;
    }
  }

  String _getStatusLabel(DeviceStatus status) {
    return status.name.toUpperCase().replaceAll('_', ' ');
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 3,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
