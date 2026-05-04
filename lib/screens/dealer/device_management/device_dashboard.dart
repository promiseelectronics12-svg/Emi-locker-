import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/device/device_model.dart';
import '../../providers/device/device_provider.dart';
import '../../services/device/device_service.dart';
import 'device_detail_screen.dart';

class DeviceDashboard extends StatelessWidget {
  const DeviceDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceProv = Provider.of<<DeviceDeviceProvider>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () => _showAlertCenter(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => deviceProv.init(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummarySection(deviceProv),
            const SizedBox(height: 24),
            const Text('Devices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...deviceProv.devices.map((device) => _DeviceListItem(device: device)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection(DeviceProvider prov) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _SummaryCard(label: 'Total Devices', value: prov.devices.length.toString(), color: Colors.blue),
        _SummaryCard(label: 'Overdue', value: prov.overdueCount.toString(), color: Colors.red),
        _SummaryCard(label: 'Upcoming EMIs', value: prov.upcomingEMIs().toString(), color: Colors.orange),
        _SummaryCard(label: 'Collection Rate', value: '${prov.collectionRate.toStringAsFixed(1)}%', color: Colors.green),
      ],
    );
  }

  void _showAlertCenter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => const AlertCenterSheet(),
    );
  }
}

class _DeviceListItem extends StatelessWidget {
  final DeviceModel device;
  const _DeviceListItem({required this.device});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('${device.model} (${device.imei})'),
      subtitle: Text('Status: ${_getStatusText(device.status)}'),
      trailing: _StatusBadge(status: device.status),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DeviceDetailScreen(device: device)),
      ),
    );
  }

  String _getStatusText(DeviceStatus status) {
    return status.name.toUpperCase();
  }
}

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case DeviceStatus.active: color = Colors.green; break;
      case DeviceStatus.reminder: color = Colors.blue; break;
      case DeviceStatus.partialLock: color = Colors.orange; break;
      case DeviceStatus.fullLock: color = Colors.red; break;
      case DeviceStatus.paidOff: color = Colors.grey; break;
      case DeviceStatus.compromised: color = Colors.purple; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(status.name, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class AlertCenterSheet extends StatelessWidget {
  const AlertCenterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Alert Center', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Divider(),
          _AlertItem(type: 'FRAUD', msg: 'Device IMEI ...456 reports unusual movement', color: Colors.red),
          _AlertItem(type: 'ADMIN', msg: 'New EMI schedule update deployed', color: Colors.blue),
          _AlertItem(type: 'ANOMALY', msg: 'Device IMEI ...123 disconnected for 48h', color: Colors.orange),
        ],
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final String type;
  final String msg;
  final Color color;
  const _AlertItem({required this.type, required this.msg, required this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, radius: 5, child: null),
      title: Text('$type: $msg', style: const TextStyle(fontSize: 14)),
    );
  }
}
