import 'package:flutter/material.dart';
import '../../models/device_management/device_model.dart';

class SummaryCards extends StatelessWidget {
  final List<<DeviceDevice> devices;

  const SummaryCards({super.key, required this.devices});

  @override
  Widget build(BuildContext context) {
    final overdueCount = devices.where((d) => d.overdueDays > 0).length;
    final totalDevices = devices.length;
    final collectionRate = totalDevices == 0 ? 0.0 : ((totalDevices - overdueCount) / totalDevices) * 100;

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildCard('Total Devices', '$totalDevices', Icons.devices, Colors.blue),
        _buildCard('Overdue', '$overdueCount', Icons.warning, Colors.red),
        _buildCard('Coll. Rate', '${collectionRate.toStringAsFixed(1)}%', Icons.trending_up, Colors.green),
        _buildCard('Upcoming', '12', Icons.calendar_today, Colors.orange),
      ],
    );
  }

  Widget _buildCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
