import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../../shared/models/device_model.dart';
import '../../../shared/models/alert_model.dart';
import '../../../shared/services/device_management_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/auth_state.dart';
import 'device_detail_screen.dart';

class DeviceDashboardScreen extends StatefulWidget {
  const DeviceDashboardScreen({super.key});

  @override
  State<DeviceDashboardScreen> createState() => _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends State<DeviceDashboardScreen> {
  late DeviceManagementService _deviceService;
  DashboardStats _stats = DashboardStats.empty();
  List<DeviceModel> _devices = [];
  List<AlertModel> _alerts = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _deviceService = context.read<DeviceManagementService>();
    _loadData();
    // Simulate real-time updates via periodic refresh (as a placeholder for Firebase Realtime DB)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final dealerId = authState.user!.id;
        
        final results = await Future.wait([
          _deviceService.getDashboardStats(dealerId),
          _deviceService.getMyDevices(dealerId),
          _deviceService.getAlerts(dealerId),
        ]);

        if (mounted) {
          setState(() {
            _stats = results[0] as DashboardStats;
            _devices = results[1] as List<Device>;
            _alerts = results[2] as List<AlertModel>;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCards(),
                  const SizedBox(height: 24),
                  _buildAlertCenter(),
                  const SizedBox(height: 24),
                  const Text(
                    'Recent Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildDeviceList(),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Devices',
          _stats.totalDevices.toString(),
          Icons.devices,
          Colors.blue,
        ),
        _buildStatCard(
          'Overdue Count',
          _stats.overdueCount.toString(),
          Icons.warning_amber_rounded,
          Colors.orange,
        ),
        _buildStatCard(
          'Upcoming (Week)',
          _stats.upcomingEmisThisWeek.toString(),
          Icons.event_note,
          Colors.purple,
        ),
        _buildStatCard(
          'Collection Rate',
          '${(_stats.collectionRate * 100).toStringAsFixed(1)}%',
          Icons.trending_up,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCenter() {
    final unreadAlerts = _alerts.where((a) => !a.isRead).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Alert Center',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (unreadAlerts.isNotEmpty)
              TextButton(
                onPressed: () => _markAllAlertsRead(),
                child: const Text('Mark all read'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_alerts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No active alerts')),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _alerts.take(3).length,
            itemBuilder: (context, index) {
              final alert = _alerts[index];
              return Card(
                color: alert.isRead ? null : Colors.red[50],
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    _getAlertIcon(alert.type),
                    color: _getAlertColor(alert.severity),
                  ),
                  title: Text(alert.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(alert.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    _formatTime(alert.createdAt),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  onTap: () => _showAlertDetails(alert),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.phonelink_erase,
        title: 'No devices enrolled',
        subtitle: 'Start by enrolling a new device',
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _devices.take(10).length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(device.status).withOpacity(0.1),
              child: Icon(Icons.phone_android, color: _getStatusColor(device.status)),
            ),
            title: Text(device.customerName),
            subtitle: Text(device.imei1),
            trailing: _buildStatusBadge(device.status),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeviceDetailScreen(deviceId: device.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(DeviceStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getStatusColor(status)),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: _getStatusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active: return Colors.green;
      case DeviceStatus.reminder: return Colors.blue;
      case DeviceStatus.partialLock: return Colors.orange;
      case DeviceStatus.fullLock: return Colors.red;
      case DeviceStatus.paidOff: return Colors.teal;
      case DeviceStatus.compromised: return Colors.black;
    }
  }

  IconData _getAlertIcon(AlertType type) {
    switch (type) {
      case AlertType.fraudAlert: return Icons.report;
      case AlertType.anomalyDetection: return Icons.analytics;
      case AlertType.adminMessage: return Icons.admin_panel_settings;
      case AlertType.paymentReminder: return Icons.payment;
      case AlertType.lockStatusChange: return Icons.lock;
    }
  }

  Color _getAlertColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.low: return Colors.blue;
      case AlertSeverity.medium: return Colors.orange;
      case AlertSeverity.high: return Colors.red;
      case AlertSeverity.critical: return Colors.purple;
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${dateTime.day}/${dateTime.month}';
  }

  void _markAllAlertsRead() async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        await _deviceService.markAllAlertsAsRead(authState.user!.id);
        _loadData(silent: true);
      }
    } catch (e) {
      // Handle error
    }
  }

  void _showAlertDetails(AlertModel alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(alert.title),
        content: Text(alert.message),
        actions: [
          TextButton(
            onPressed: () {
              _deviceService.markAlertAsRead(alert.id);
              Navigator.pop(context);
              _loadData(silent: true);
            },
            child: const Text('Dismiss'),
          ),
          if (alert.deviceId.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceDetailScreen(deviceId: alert.deviceId),
                  ),
                );
              },
              child: const Text('View Device'),
            ),
        ],
      ),
    );
  }
}
