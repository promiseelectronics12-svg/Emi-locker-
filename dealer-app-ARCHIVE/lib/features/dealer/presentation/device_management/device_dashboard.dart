import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/models/alert_model.dart';
import '../../../../shared/services/device_management_service.dart';
import '../../../../shared/services/firebase_service.dart';
import 'widgets/summary_card.dart';
import 'widgets/device_list_tile.dart';
import 'widgets/alert_center_sheet.dart';
import 'device_detail_screen.dart';

class DeviceDashboard extends StatefulWidget {
  final String dealerId;

  const DeviceDashboard({super.key, required this.dealerId});

  @override
  State<DeviceDashboard> createState() => _DeviceDashboardState();
}

class _DeviceDashboardState extends State<DeviceDashboard> {
  final DeviceManagementService _deviceService = DeviceManagementService();
  final FirebaseService _firebaseService = FirebaseService();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  StreamSubscription<DatabaseEvent>? _devicesSubscription;
  StreamSubscription<DatabaseEvent>? _alertsSubscription;

  List<Device> _devices = [];
  DashboardStats _stats = DashboardStats.empty();
  List<AlertModel> _alerts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initDashboard();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _alertsSubscription?.cancel();
    _firebaseService.dispose();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _deviceService.getMyDevices(widget.dealerId),
        _deviceService.getDashboardStats(widget.dealerId),
        _deviceService.getAlerts(widget.dealerId),
      ]);

      setState(() {
        _devices = results[0] as List<Device>;
        _stats = results[1] as DashboardStats;
        _alerts = results[2] as List<AlertModel>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _setupRealtimeListeners() {
    _devicesSubscription = _dbRef
        .child('dealers')
        .child(widget.dealerId)
        .child('devices')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
            event.snapshot.value as Map);
        final updatedDevices = data.entries.map((e) {
          return Device.fromJson(Map<String, dynamic>.from(e.value));
        }).toList();

        setState(() {
          _devices = updatedDevices;
        });
      }
    }, onError: (error) {
      debugPrint('Device stream error: $error');
    });

    _alertsSubscription = _dbRef
        .child('dealers')
        .child(widget.dealerId)
        .child('alerts')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
            event.snapshot.value as Map);
        final updatedAlerts = data.entries.map((e) {
          return AlertModel.fromJson(Map<String, dynamic>.from(e.value));
        }).toList();

        setState(() {
          _alerts = updatedAlerts;
        });
      }
    }, onError: (error) {
      debugPrint('Alerts stream error: $error');
    });
  }

  Future<void> _refreshDashboard() async {
    await _initDashboard();
  }

  void _showAlertCenter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AlertCenterSheet(
        alerts: _alerts,
        onMarkRead: _markAlertAsRead,
        onDismiss: _dismissAlert,
      ),
    );
  }

  Future<void> _markAlertAsRead(String alertId) async {
    try {
      await _deviceService.markAlertAsRead(alertId);
      setState(() {
        _alerts.removeWhere((a) => a.id == alertId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking alert as read: $e')),
        );
      }
    }
  }

  void _dismissAlert(String alertId) {
    setState(() {
      _alerts.removeWhere((a) => a.id == alertId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Management'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: _showAlertCenter,
            tooltip: 'Alert Center',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDashboard,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load dashboard',
              style: TextStyle(color: Colors.red[700], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshDashboard,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummarySection(),
            const SizedBox(height: 24),
            _buildAlertCenterButton(),
            const SizedBox(height: 24),
            _buildDeviceListHeader(),
            const SizedBox(height: 12),
            _buildDeviceList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        SummaryCard(
          title: 'Total Devices',
          value: _stats.totalDevices.toString(),
          icon: Icons.devices,
          color: Colors.blue,
        ),
        SummaryCard(
          title: 'Overdue',
          value: _stats.overdueCount.toString(),
          icon: Icons.warning_amber,
          color: Colors.red,
        ),
        SummaryCard(
          title: 'Upcoming EMIs',
          value: _stats.upcomingEmisThisWeek.toString(),
          icon: Icons.calendar_today,
          color: Colors.orange,
        ),
        SummaryCard(
          title: 'Collection Rate',
          value: '${(_stats.collectionRate * 100).toStringAsFixed(1)}%',
          icon: Icons.trending_up,
          color: Colors.green,
        ),
      ],
    );
  }

  Widget _buildAlertCenterButton() {
    final unreadCount = _alerts.where((a) => !a.isRead).length;

    return GestureDetector(
      onTap: _showAlertCenter,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: unreadCount > 0 ? Colors.red[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: unreadCount > 0 ? Colors.red : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Icon(
                  Icons.notifications_active,
                  color: unreadCount > 0 ? Colors.red : Colors.grey,
                  size: 28,
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alert Center',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    unreadCount > 0
                        ? '$unreadCount unread alert${unreadCount > 1 ? 's' : ''}'
                        : 'No new alerts',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Managed Devices',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          '${_devices.length} device${_devices.length != 1 ? 's' : ''}',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.phone_android, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No devices enrolled yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Devices will appear here once enrolled',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return DeviceListTile(
          device: device,
          onTap: () => _navigateToDeviceDetail(device),
        );
      },
    );
  }

  void _navigateToDeviceDetail(Device device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(
          device: device,
          dealerId: widget.dealerId,
        ),
      ),
    );
  }
}