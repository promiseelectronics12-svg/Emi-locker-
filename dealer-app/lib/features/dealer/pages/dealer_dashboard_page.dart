import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/models/device.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/firebase_service.dart';
import 'dart:async';

class DealerDashboardPage extends StatefulWidget {
  const DealerDashboardPage({super.key});

  @override
  State<DealerDashboardPage> createState() => _DealerDashboardPageState();
}

class _DealerDashboardPageState extends State<DealerDashboardPage> {
  final ApiClient _apiClient = ApiClient();
  final FirebaseService _firebaseService = FirebaseService();

  List<Device> _devices = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _setupRealtimeUpdates();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _firebaseService.unsubscribeFromDeviceStatus();
    super.dispose();
  }

  void _setupRealtimeUpdates() {
    _firebaseService.deviceStatusStream.listen((device) {
      setState(() {
        final index = _devices.indexWhere((d) => d.id == device.id);
        if (index >= 0) {
          _devices[index] = device;
        }
      });
    });
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = await _firebaseService.getStoredUserId();
      if (userId != null) {
        await _firebaseService.subscribeToDeviceStatus(userId);
      }

      final response = await _apiClient.get('/devices');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['devices'] as List<dynamic>;
        setState(() {
          _devices = data
              .map((json) => Device.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  int get _activeDevicesCount =>
      _devices.where((d) => d.status == DeviceStatus.active).length;

  int get _lockedDevicesCount =>
      _devices.where((d) => d.status == DeviceStatus.locked).length;

  int get _overduePaymentsCount =>
      _devices.where((d) => d.isPaymentOverdue).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealer Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () {
              Navigator.pushNamed(context, '/enroll-device');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDevices,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDevices,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      'Active',
                                      _activeDevicesCount.toString(),
                                      AppTheme.successColor,
                                      Icons.check_circle_outline,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      'Locked',
                                      _lockedDevicesCount.toString(),
                                      AppTheme.errorColor,
                                      Icons.lock_outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      'Overdue',
                                      _overduePaymentsCount.toString(),
                                      AppTheme.warningColor,
                                      Icons.warning_amber_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatCard(
                                      'Total',
                                      _devices.length.toString(),
                                      AppTheme.primaryColor,
                                      Icons.devices,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent Devices',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/devices');
                                },
                                child: const Text('View All'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_devices.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                            child: Text(
                              'No devices enrolled yet.\nTap + to enroll a new device.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final device = _devices[index];
                              return _buildDeviceCard(device);
                            },
                            childCount: _devices.length > 5 ? 5 : _devices.length,
                          ),
                        ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/enroll-device');
        },
        icon: const Icon(Icons.add),
        label: const Text('Enroll Device'),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(Device device) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(device.status),
          child: Icon(
            _getStatusIcon(device.status),
            color: Colors.white,
          ),
        ),
        title: Text(
          device.customerName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IMEI: ${device.imei1}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${device.paidAmount.toStringAsFixed(0)} / ${device.totalAmount.toStringAsFixed(0)} BDT',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(device.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${device.paymentProgress.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: _getStatusColor(device.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/device-detail',
            arguments: device,
          );
        },
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.pendingDecouple:
        return Colors.orange;
      case DeviceStatus.decoupled:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return Icons.check_circle;
      case DeviceStatus.locked:
        return Icons.lock;
      case DeviceStatus.gracePeriod:
        return Icons.access_time;
      case DeviceStatus.pendingDecouple:
        return Icons.hourglass_empty;
      case DeviceStatus.decoupled:
        return Icons.power_settings_new;
    }
  }
}