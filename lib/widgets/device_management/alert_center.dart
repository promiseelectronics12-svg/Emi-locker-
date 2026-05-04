import 'package:flutter/material.dart';

class AlertCenter extends StatelessWidget {
  const AlertCenter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Security & Admin Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _buildAlert('FRAUD ALERT', 'Device IMEI ...4421 reported as compromised', Colors.red, Icons.report_problem),
        _buildAlert('ADMIN MSG', 'New BTRC NEIR update available', Colors.blue, Icons.message),
        _buildAlert('ANOMALY', 'Unexpected GPS jump detected for Device #902', Colors.orange, Icons.warning),
      ],
    );
  }

  Widget _buildAlert(String tag, String message, Color color, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(tag, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        subtitle: Text(message),
        trailing: const Icon(Icons.chevron_right, size: 16),
      ),
    );
  }
}
