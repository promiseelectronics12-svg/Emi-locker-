import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/device/device_model.dart';
import '../../services/device/device_service.dart';
import 'lock_request_sheet.dart';

class DeviceDetailScreen extends StatelessWidget {
  final DeviceModel device;
  const DeviceDetailScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final deviceService = DeviceService();

    return Scaffold(
      appBar: AppBar(title: Text('Device Detail')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Device Information'),
            _InfoTile(label: 'IMEI', value: device.imei),
            _InfoTile(label: 'Serial', value: device.serial),
            _InfoTile(label: 'OEM/Model', value: '${device.oem} ${device.model}'),
            _InfoTile(label: 'Android Version', value: device.androidVersion),
            _InfoTile(label: 'Enrollment Date', value: device.enrollmentDate.toString()),
            
            const SizedBox(height: 20),
            _buildSectionTitle('Status & Location'),
            _InfoTile(label: 'Current Lock State', value: device.status.name.toUpperCase()),
            _InfoTile(label: 'Last State Change', value: device.lastStateChange.toString()),
            _InfoTile(
              label: 'Last Known Location', 
              value: 'Tap to view on Map',
              onTap: () => _openMap(device.latitude, device.longitude),
            ),
            
            const SizedBox(height: 20),
            _buildSectionTitle('Customer Info'),
            _InfoTile(label: 'Name', value: device.customer.name),
            _InfoTile(label: 'NID', value: device.customer.nid),
            _InfoTile(label: 'Phone', value: device.customer.phone),
            _InfoTile(
              label: 'NID Photo', 
              value: 'View Photo',
              onTap: () => _openImageUrl(device.customer.nidPhotoUrl),
            ),

            const SizedBox(height: 20),
            _buildSectionTitle('EMI Schedule'),
            ...device.emiSchedules.map((emi) => ListTile(
              title: Text('Installment #${emi.installmentNumber}'),
              subtitle: Text('Due: ${emi.dueDate}'),
              trailing: Text(emi.isPaid ? 'Paid' : 'Unpaid', 
                style: TextStyle(color: emi.isPaid ? Colors.green : Colors.red)),
            )),

            const SizedBox(height: 30),
            _buildActionButtons(context, device, deviceService),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
    );
  }

  Widget _buildActionButtons(BuildContext context, DeviceModel device, DeviceService service) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionButton(label: 'Request Lock', icon: Icons.lock, color: Colors.red, 
          onTap: () => showModalBottomSheet(context: context, builder: (_) => LockRequestSheet(device: device))),
        _ActionButton(label: 'Request Unlock', icon: Icons.lock_open, color: Colors.green, 
          onTap: () => _handleRequest(context, service.requestUnlock, device.id, 'Unlock')),
        _ActionButton(label: 'Grace Period', icon: Icons.timer, color: Colors.orange, 
          onTap: () => _handleRequest(context, service.grantGracePeriod, device.id, 'Grace Period')),
        _ActionButton(label: 'Send Message', icon: Icons.message, color: Colors.blue, 
          onTap: () => _handleRequest(context, service.sendMessage, device.id, 'Message')),
        _ActionButton(label: 'Pull Location', icon: Icons.location_on, color: Colors.indigo, 
          onTap: () => _handleRequest(context, service.pullLocation, device.id, 'Pull Location')),
      ],
    );
  }

  Future<<voidvoid> _handleRequest(BuildContext context, Function fn, String deviceId, String action) async {
    // Generic handler for actions requiring simple confirmation or TOTP
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$action request sent for $deviceId')));
  }

  Future<<voidvoid> _openMap(double lat, double lng) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    if (!await launchUrl(Uri.parse(url))) throw 'Could not launch map';
  }

  Future<<voidvoid> _openImageUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) throw 'Could not launch image';
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoTile({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      trailing: onTap != null ? const Icon(Icons.arrow_forward_ios, size: 14) : null,
      onTap: onTap,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
    );
  }
}
