import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../bloc/device_bloc.dart';
import '../bloc/device_state.dart';
import '../../../shared/models/device.dart';
import 'device_detail_screen.dart';

class DeviceDashboard extends StatelessWidget {
  const DeviceDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh logic
            },
          ),
        ],
      ),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          if (state.status == DeviceStatusType.loading && state.devices.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              // Trigger refresh
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummarySection(state),
                  const SizedBox(height: 24),
                  _buildAlertCenter(state),
                  const SizedBox(height: 24),
                  const Text(
                    'All Devices',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDeviceList(context, state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummarySection(DeviceState state) {
    final total = state.devices.length;
    final overdue = state.devices.where((d) => d.isPaymentOverdue).length;
    final upcomingThisWeek = state.devices.where((d) {
      final now = DateTime.now();
      final weekFromNow = now.add(const Duration(days: 7));
      return d.nextPaymentDate.isAfter(now) && d.nextPaymentDate.isBefore(weekFromNow);
    }).length;
    
    // Collection rate calculation
    double collectionRate = 0;
    if (total > 0) {
      final totalPaid = state.devices.fold(0, (sum, d) => sum + d.paidInstallments);
      final totalPossible = state.devices.fold(0, (sum, d) => sum + d.totalInstallments);
      collectionRate = totalPossible > 0 ? (totalPaid / totalPossible) * 100 : 0;
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _SummaryCard(
          title: 'Total Devices',
          value: total.toString(),
          icon: Icons.phone_android,
          color: AppTheme.primaryColor,
        ),
        _SummaryCard(
          title: 'Overdue EMIs',
          value: overdue.toString(),
          icon: Icons.warning_amber_rounded,
          color: AppTheme.errorColor,
        ),
        _SummaryCard(
          title: 'Upcoming (Week)',
          value: upcomingThisWeek.toString(),
          icon: Icons.calendar_today,
          color: AppTheme.warningColor,
        ),
        _SummaryCard(
          title: 'Collection Rate',
          value: '${collectionRate.toStringAsFixed(1)}%',
          icon: Icons.trending_up,
          color: AppTheme.successColor,
        ),
      ],
    );
  }

  Widget _buildAlertCenter(DeviceState state) {
    if (state.alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Alert Center',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: state.alerts.length,
            itemBuilder: (context, index) {
              final alert = state.alerts[index];
              return _AlertItem(alert: alert);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceList(BuildContext context, DeviceState state) {
    if (state.devices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.devices_other, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('No devices enrolled yet', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: state.devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final device = state.devices[index];
        return _DeviceListItem(
          device: device,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceDetailScreen(deviceId: device.id),
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertItem extends StatelessWidget {
  final dynamic alert; // AlertModel

  const _AlertItem({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        color: _getAlertColor(alert.severity).withOpacity(0.05),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _getAlertColor(alert.severity).withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getAlertIcon(alert.type),
                    size: 16,
                    color: _getAlertColor(alert.severity),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getAlertColor(alert.severity),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                alert.message,
                style: const TextStyle(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAlertColor(dynamic severity) {
    // Mock severities or use from AlertModel
    return AppTheme.errorColor;
  }

  IconData _getAlertIcon(dynamic type) {
    return Icons.warning;
  }
}

class _DeviceListItem extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const _DeviceListItem({
    required this.device,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getStatusColor(device.status).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.phone_android,
            color: _getStatusColor(device.status),
          ),
        ),
        title: Text(
          device.customerName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${device.model} • ${device.imei1}'),
            const SizedBox(height: 4),
            _StatusBadge(status: device.status),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: true,
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.reminder:
        return AppTheme.warningColor;
      case DeviceStatus.partialLock:
        return Colors.orange;
      case DeviceStatus.fullLock:
        return AppTheme.errorColor;
      case DeviceStatus.paidOff:
        return Colors.blue;
      case DeviceStatus.compromised:
        return Colors.purple;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final DeviceStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          color: _getColor(),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.reminder:
        return AppTheme.warningColor;
      case DeviceStatus.partialLock:
        return Colors.orange;
      case DeviceStatus.fullLock:
        return AppTheme.errorColor;
      case DeviceStatus.paidOff:
        return Colors.blue;
      case DeviceStatus.compromised:
        return Colors.purple;
    }
  }

  String _getLabel() {
    switch (status) {
      case DeviceStatus.active:
        return 'ACTIVE';
      case DeviceStatus.reminder:
        return 'REMINDER';
      case DeviceStatus.partialLock:
        return 'PARTIAL LOCK';
      case DeviceStatus.fullLock:
        return 'FULL LOCK';
      case DeviceStatus.paidOff:
        return 'PAID OFF';
      case DeviceStatus.compromised:
        return 'COMPROMISED';
    }
  }
}
