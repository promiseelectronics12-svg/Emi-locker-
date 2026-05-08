import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../shared/models/device.dart';
import '../../../shared/models/user.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/firebase_service.dart';
import '../../auth/bloc/auth_bloc.dart';

class DealerDashboardScreen extends StatefulWidget {
  final User user;

  const DealerDashboardScreen({super.key, required this.user});

  @override
  State<DealerDashboardScreen> createState() => _DealerDashboardScreenState();
}

class _DealerDashboardScreenState extends State<DealerDashboardScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Device> _devices = [];
  bool _isLoading = true;
  Map<String, dynamic> _analytics = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    _firebaseService.unsubscribeFromDeviceStatus();
    super.dispose();
  }

  Future<void> _subscribeToUpdates() async {
    await _firebaseService.subscribeToDeviceStatus(widget.user.id);
    _firebaseService.deviceStatusStream.listen((data) {
      _updateDeviceFromRealtime(data);
    });
  }

  void _updateDeviceFromRealtime(Map<String, dynamic> data) {
    final index = _devices.indexWhere((d) => d.id == data['id']);
    if (index != -1) {
      setState(() {
        _devices[index] = Device.fromJson(data);
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient();
      final response = await apiClient.get('/dealer/devices');
      if (response.statusCode == 200) {
        final List<dynamic> devicesJson = response.data['devices'] ?? [];
        _devices = devicesJson
            .map((json) => Device.fromJson(json as Map<String, dynamic>))
            .toList();
        _analytics = Map<String, dynamic>.from(response.data['analytics'] ?? {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load devices'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  int get _activeDevices =>
      _devices.where((d) => d.status == DeviceStatus.active).length;
  int get _lockedDevices =>
      _devices.where((d) => d.status == DeviceStatus.locked).length;
  int get _gracePeriodDevices =>
      _devices.where((d) => d.status == DeviceStatus.gracePeriod).length;

  double get _totalCollection = _devices.fold(0, (sum, d) => sum + d.paidAmount);
  double get _totalOutstanding =
      _devices.fold(0, (sum, d) => sum + d.remainingAmount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealer Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                context.read<AuthBloc>().add(AuthLogoutRequested());
              } else if (value == 'password') {
                Navigator.pushNamed(context, '/change-password');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'password',
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Change Password'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeCard(),
                    const SizedBox(height: 16),
                    _buildStatsRow(),
                    const SizedBox(height: 16),
                    _buildCollectionCard(),
                    const SizedBox(height: 16),
                    _buildStatusChart(),
                    const SizedBox(height: 16),
                    _buildRecentDevices(),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/enroll-device'),
        icon: const Icon(Icons.add),
        label: const Text('Enroll Device'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppTheme.primaryLight,
              child: Text(
                widget.user.name.isNotEmpty
                    ? widget.user.name[0].toUpperCase()
                    : 'D',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${widget.user.name}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user.shopName ?? 'Dealer Account',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Keys: ${widget.user.availableKeys} available',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Active',
            _activeDevices.toString(),
            Icons.check_circle_outline,
            AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Locked',
            _lockedDevices.toString(),
            Icons.lock_outline,
            AppTheme.errorColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Grace',
            _gracePeriodDevices.toString(),
            Icons.warning_amber_outlined,
            AppTheme.warningColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collection Overview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Collected',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '৳${_totalCollection.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.successColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Outstanding',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    Text(
                      '৳${_totalOutstanding.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChart() {
    if (_devices.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Status Distribution',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfPieChart(
                series: <PieSeries<DeviceStatusData, String>>[
                  PieSeries<DeviceStatusData, String>(
                    dataSource: [
                      DeviceStatusData('Active', _activeDevices),
                      DeviceStatusData('Locked', _lockedDevices),
                      DeviceStatusData('Grace', _gracePeriodDevices),
                    ],
                    xValueMapper: (datum, index) => datum.status,
                    yValueMapper: (datum, index) => datum.count,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartDataLabelPosition.outside,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentDevices() {
    final recentDevices = _devices.take(5).toList();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Devices',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/devices'),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          if (recentDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No devices enrolled yet'),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentDevices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = recentDevices[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        DeviceStatusColors.getColor(device.status.name),
                    child: const Icon(Icons.phone_android, color: Colors.white),
                  ),
                  title: Text(device.customerName),
                  subtitle: Text(device.imei1),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: DeviceStatusColors.getColor(device.status.name)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      device.statusDisplayName,
                      style: TextStyle(
                        color: DeviceStatusColors.getColor(device.status.name),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/device-details',
                    arguments: device,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class DeviceStatusData {
  final String status;
  final int count;

  DeviceStatusData(this.status, this.count);
}
