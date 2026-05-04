import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/models/emi_schedule_model.dart';
import 'lock_request_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  List<EMIScheduleModel> _emiSchedule = [];
  bool _loadingEmi = true;
  Map<String, dynamic>? _gpsData;

  @override
  void initState() {
    super.initState();
    _loadEmiSchedule();
    _loadGpsLocation();
  }

  Future<void> _loadEmiSchedule() async {
    try {
      final response = await Injection.apiClient.get(
        '/api/v1/devices/${widget.device.id}/emi-schedule',
      );
      setState(() {
        _emiSchedule = (response.data as List)
            .map((e) => EMIScheduleModel.fromJson(e))
            .toList();
        _loadingEmi = false;
      });
    } catch (_) {
      setState(() => _loadingEmi = false);
    }
  }

  Future<void> _loadGpsLocation() async {
    try {
      final response = await Injection.apiClient.get(
        '/api/v1/devices/${widget.device.id}/gps',
      );
      setState(() => _gpsData = response.data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Scaffold(
      appBar: AppBar(
        title: Text(d.model ?? 'Device Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadEmiSchedule();
              _loadGpsLocation();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusChip(d.status),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Info',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    _infoRow('IMEI', d.imei),
                    _infoRow('Brand', d.brand ?? 'Unknown'),
                    _infoRow('Model', d.model ?? 'Unknown'),
                    _infoRow('Status', d.status.toUpperCase()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Owner Info',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    _infoRow('Name', d.ownerName ?? 'Not assigned'),
                    _infoRow('Phone', d.ownerPhone ?? '-'),
                    _infoRow('NID', d.ownerNid ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
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
                    _infoRow('Monthly', '৳${d.monthlyAmount ?? 0}'),
                    _infoRow('Total Months', '${d.emiTotalMonths ?? 0}'),
                    _infoRow('Months Paid', '${d.emiMonthsPaid ?? 0}'),
                    _infoRow('Remaining', '${d.emiRemaining ?? 0}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_gpsData != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Known Location',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Divider(),
                      _infoRow('Latitude', '${_gpsData!['latitude'] ?? '-'}'),
                      _infoRow('Longitude', '${_gpsData!['longitude'] ?? '-'}'),
                      _infoRow('Updated', _gpsData!['updated_at'] ?? '-'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMI Schedule',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    if (_loadingEmi)
                      const Center(child: CircularProgressIndicator())
                    else if (_emiSchedule.isEmpty)
                      const Text('No EMI schedule found')
                    else
                      ...List.generate(_emiSchedule.length, (i) {
                        final emi = _emiSchedule[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            emi.isPaid
                                ? Icons.check_circle
                                : emi.isOverdue
                                ? Icons.warning
                                : Icons.schedule,
                            color: emi.isPaid
                                ? Colors.green
                                : emi.isOverdue
                                ? Colors.red
                                : Colors.orange,
                            size: 20,
                          ),
                          title: Text('Month ${emi.monthNumber}'),
                          trailing: Text('৳${emi.amount}'),
                          subtitle: Text(
                            emi.isPaid ? 'Paid' : emi.status.toUpperCase(),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (d.isActive)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LockRequestScreen(device: d),
                    ),
                  ),
                  icon: const Icon(Icons.lock),
                  label: const Text('Request Lock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'active':
        color = Colors.green;
        break;
      case 'locked':
        color = Colors.red;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: color,
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
