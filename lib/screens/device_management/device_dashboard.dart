import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/device_management/device_service.dart';
import '../../models/device_management/device_model.dart';
import '../../widgets/device_management/summary_cards.dart';
import '../../widgets/device_management/alert_center.dart';
import '../../widgets/device_management/device_status_badge.dart';
import 'device_detail_screen.dart';

class DeviceDashboard extends StatefulWidget {
  const DeviceDashboard({super.key});

  @override
  State<<<DeviceDeviceDashboard> DeviceDashboardState get createState() => DeviceDashboardState();
}

class DeviceDashboardState extends State<<<DeviceDeviceDashboard> {
  final DeviceService _deviceService = DeviceService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Management')),
      body: StreamBuilder<<<ListList<<<DeviceDevice>>>(
        stream: _deviceService.getDevicesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final devices = snapshot.data!;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SummaryCards(devices: devices),
                const SizedBox(height: 24),
                const AlertCenter(),
                const SizedBox(height: 24),
                const Text('Managed Devices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      child: ListTile(
                        title: Text('${device.model} (${device.customerName})'),
                        subtitle: Text('IMEI: ${device.imei}'),
                        trailing: DeviceStatusBadge(status: device.status),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DeviceDetailScreen(device: device)),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
