import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/device_management/device_model.dart';
import 'lock_request_sheet.dart';

class DeviceDetailScreen extends StatelessWidget {
  final Device device;

  const DeviceDetailScreen({super.key, required this.device});

  Future<<<<voidvoid> _openMap() async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${device.lastLat},${device.lastLng}');
    if (!await launchUrl(url)) {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Device ${device.imei}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Device Information'),
            _buildInfoRow('IMEI', device.imei),
            _buildInfoRow('Serial', device.serial),
            _buildInfoRow('OEM/Model', '${device.oem} ${device.model}'),
            _buildInfoRow('Android', device.androidVersion),
            _buildInfoRow('Enrollment', device.enrollmentDate),
            _buildInfoRow('Current State', device.status),
            _buildInfoRow('Last State Change', device.lastStateChange),
            
            const SizedBox(height: 20),
            _buildSectionTitle('Location'),
            ListTile(
              leading: const Icon(Icons.location_on),
              title: Text('Last Known: ${device.lastLocationTime}'),
              subtitle: Text('${device.lastLat}, ${device.lastLng}'),
              trailing: TextButton(onPressed: _openMap, child: const Text('Open Maps')),
            ),

            const SizedBox(height: 20),
            _buildSectionTitle('Customer Details'),
            _buildInfoRow('Name', device.customerName),
            _buildInfoRow('NID', device.customerNid),
            _buildInfoRow('Phone', device.customerPhone),
            _buildInfoRow('NID Photo', 'View Photo', isAction: true),

            const SizedBox(height: 20),
            _buildSectionTitle('EMI Schedule'),
            ...device.emiSchedule.map((emi) => ListTile(
              title: Text('Due: ${emi.dueDate}'),
              subtitle: Text('Amount: ${emi.amount} BDT'),
              trailing: Text(emi.status, style: TextStyle(color: emi.status == 'Unpaid' ? Colors.red : Colors.green)),
            )),

            const SizedBox(height: 30),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionButton(context, 'Request Lock', () => _showLockSheet(context)),
                _buildActionButton(context, 'Request Unlock', () {}),
                _buildActionButton(context, 'Grace Period', () {}),
                _buildActionButton(context, 'Send Msg', () {}),
                _buildActionButton(context, 'Pull Loc', () {}),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isAction = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          GestureDetector(
            onTap: isAction ? () {} : null,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w500, color: isAction ? Colors.blue : Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      child: Text(label),
    );
  }

  void _showLockSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LockRequestSheet(device: device),
    );
  }
}
