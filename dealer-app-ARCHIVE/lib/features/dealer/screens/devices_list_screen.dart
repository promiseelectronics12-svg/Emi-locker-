import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/constants/constants.dart';
import '../bloc/dealer_bloc.dart';

class DevicesListScreen extends StatefulWidget {
  const DevicesListScreen({super.key});

  @override
  State<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends State<DevicesListScreen> {
  final _searchController = TextEditingController();
  String? _selectedStatus;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    context.read<DealerBloc>().add(const LoadDevices());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    context.read<DealerBloc>().add(
          LoadDevices(
            page: 1,
            search: query.isNotEmpty ? query : null,
            status: _selectedStatus,
          ),
        );
  }

  void _onStatusFilter(String? status) {
    setState(() => _selectedStatus = status);
    context.read<DealerBloc>().add(
          LoadDevices(
            page: 1,
            status: status,
            search: _searchController.text.isNotEmpty
                ? _searchController.text
                : null,
          ),
        );
  }

  void _loadMore() {
    final state = context.read<DealerBloc>().state;
    if (!state.isLoading && state.hasMoreDevices) {
      _currentPage++;
      context.read<DealerBloc>().add(
            LoadDevices(
              page: _currentPage,
              status: _selectedStatus,
              search:
                  _searchController.text.isNotEmpty ? _searchController.text : null,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DealerBloc, DealerState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by IMEI, customer name or phone',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                            )
                          : null,
                    ),
                    onSubmitted: _onSearch,
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          isSelected: _selectedStatus == null,
                          onTap: () => _onStatusFilter(null),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Active',
                          isSelected: _selectedStatus == DeviceStatus.active,
                          color: AppTheme.successColor,
                          onTap: () => _onStatusFilter(DeviceStatus.active),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Locked',
                          isSelected: _selectedStatus == DeviceStatus.locked,
                          color: AppTheme.errorColor,
                          onTap: () => _onStatusFilter(DeviceStatus.locked),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Grace Period',
                          isSelected: _selectedStatus == DeviceStatus.gracePeriod,
                          color: AppTheme.warningColor,
                          onTap: () => _onStatusFilter(DeviceStatus.gracePeriod),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'Decoupling',
                          isSelected: _selectedStatus == DeviceStatus.decoupling,
                          color: Colors.purple,
                          onTap: () => _onStatusFilter(DeviceStatus.decoupling),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.isLoading && state.devices.isEmpty
                  ? const LoadingWidget(message: 'Loading devices...')
                  : state.devices.isEmpty
                      ? EmptyStateWidget(
                          icon: Icons.phone_android,
                          title: 'No devices found',
                          subtitle: _searchController.text.isNotEmpty
                              ? 'Try a different search term'
                              : 'Start by enrolling your first device',
                          actionLabel: 'Enroll Device',
                          onAction: () =>
                              Navigator.pushNamed(context, '/dealer/enroll'),
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            context
                                .read<DealerBloc>()
                                .add(const LoadDevices());
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: state.devices.length +
                                (state.hasMoreDevices ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == state.devices.length) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: state.isLoading
                                        ? const CircularProgressIndicator()
                                        : TextButton(
                                            onPressed: _loadMore,
                                            child: const Text('Load More'),
                                          ),
                                  ),
                                );
                              }

                              final device = state.devices[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: DeviceCard(
                                  title: device.customerName,
                                  subtitle: device.imei1,
                                  status: device.status,
                                  secondaryText:
                                      '${device.currentTenure}/${device.tenureMonths} months',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/dealer/device/${device.id}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? (color ?? AppTheme.primaryColor) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? (color ?? AppTheme.primaryColor)
                : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimaryColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DealerBloc>().add(LoadDeviceDetail(deviceId: widget.deviceId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DealerBloc, DealerState>(
      builder: (context, state) {
        if (state.isLoading && state.selectedDevice == null) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading device details...'),
          );
        }

        final device = state.selectedDevice;
        if (device == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Device Details')),
            body: const ErrorDisplayWidget(message: 'Device not found'),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(device.customerName),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context
                    .read<DealerBloc>()
                    .add(LoadDeviceDetail(deviceId: widget.deviceId)),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.phone_android,
                                color: AppTheme.primaryColor,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.customerName,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  StatusBadge(status: device.status),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        _InfoRow(label: 'IMEI 1', value: device.imei1),
                        if (device.imei2 != null)
                          _InfoRow(label: 'IMEI 2', value: device.imei2!),
                        _InfoRow(label: 'MAC Address', value: device.macAddress),
                        _InfoRow(label: 'Phone', value: device.customerPhone),
                        _InfoRow(label: 'NID', value: device.customerNid),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EMI Progress',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: device.paymentProgress,
                          backgroundColor: Colors.grey.shade200,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '৳${device.paidAmount.toStringAsFixed(0)} paid',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              '৳${device.remainingAmount.toStringAsFixed(0)} remaining',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: 'Total',
                                value: '৳${device.totalAmount.toStringAsFixed(0)}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatCard(
                                label: 'Monthly',
                                value: '৳${device.monthlyInstallment.toStringAsFixed(0)}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatCard(
                                label: 'Remaining',
                                value: '${device.remainingMonths} mo',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment Schedule',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        if (device.nextPaymentDate != null)
                          _InfoRow(
                            label: 'Next Payment',
                            value: DateFormat('dd MMM yyyy')
                                .format(device.nextPaymentDate!),
                          ),
                        if (device.lastPaymentDate != null)
                          _InfoRow(
                            label: 'Last Payment',
                            value: DateFormat('dd MMM yyyy')
                                .format(device.lastPaymentDate!),
                          ),
                        if (device.enrolledAt != null)
                          _InfoRow(
                            label: 'Enrolled',
                            value: DateFormat('dd MMM yyyy')
                                .format(device.enrolledAt!),
                          ),
                      ],
                    ),
                  ),
                ),
                if (device.hasLocation) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device Location',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.location_on,
                                      color: AppTheme.primaryColor, size: 40),
                                  const SizedBox(height: 8),
                                  Text(
                                    device.location ?? 'Unknown',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  Text(
                                    '${device.latitude}, ${device.longitude}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (device.isActive || device.isInGracePeriod) ...[
                  ElevatedButton.icon(
                    onPressed: () => _showLockRequestDialog(context, device),
                    icon: const Icon(Icons.lock),
                    label: const Text('Request Device Lock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
                if (device.isLocked) ...[
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock),
                    label: const Text('Lock Request Submitted'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLockRequestDialog(BuildContext context, device) {
    String? selectedReason;
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request Device Lock'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a reason for the lock request:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...LockReasons.labels.entries.map((entry) {
                return RadioListTile<String>(
                  title: Text(entry.value),
                  subtitle: Text(LockReasons.descriptions[entry.key] ?? ''),
                  value: entry.key,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    (dialogContext as Element).markNeedsBuild();
                    setState(() => selectedReason = value);
                  },
                );
              }),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Additional Note (optional)',
                  hintText: 'Max 200 characters',
                ),
                maxLength: 200,
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Text(
                'Note: Lock requests are verified by the server. Invalid requests will be rejected.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.warningColor,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: selectedReason == null
                ? null
                : () {
                    context.read<DealerBloc>().add(
                          SubmitLockRequest(
                            deviceId: device.id,
                            reasonCode: selectedReason!,
                            note: noteController.text.isNotEmpty
                                ? noteController.text
                                : null,
                          ),
                        );
                    Navigator.pop(dialogContext);
                  },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DealerBloc>().add(LoadAnalytics());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DealerBloc, DealerState>(
      builder: (context, state) {
        if (state.isLoading && state.analytics == null) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading analytics...'),
          );
        }

        final analytics = state.analytics;
        if (analytics == null) {
          return const Scaffold(
            body: ErrorDisplayWidget(message: 'Failed to load analytics'),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Business Analytics',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  ProgressCard(
                    title: 'Total Revenue',
                    value: '৳${analytics.totalRevenue.toStringAsFixed(0)}',
                    icon: Icons.attach_money,
                    color: AppTheme.successColor,
                  ),
                  ProgressCard(
                    title: 'Pending Amount',
                    value: '৳${analytics.pendingAmount.toStringAsFixed(0)}',
                    icon: Icons.hourglass_empty,
                    color: AppTheme.warningColor,
                  ),
                  ProgressCard(
                    title: 'New This Month',
                    value: analytics.newDevicesThisMonth.toString(),
                    icon: Icons.add_circle,
                    color: AppTheme.primaryColor,
                  ),
                  ProgressCard(
                    title: 'Decoupled',
                    value: analytics.decoupledThisMonth.toString(),
                    icon: Icons.link_off,
                    color: Colors.purple,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Status Overview',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: SfPieChart(
                          series: [
                            PieSeries<String, int>(
                              dataSource: analytics.statusBreakdown
                                  .map((e) => e.status)
                                  .toList()
                                  .asMap()
                                  .entries
                                  .map((e) => '${e.value}:${analytics.statusBreakdown[e.key].count}')
                                  .toList(),
                              xValueMapper: (datum, index) => datum.toString(),
                              yValueMapper: (datum, index) =>
                                  int.tryParse(datum.toString().split(':').last) ?? 0,
                              dataLabelMapper: (datum, index) =>
                                  datum.toString().split(':').first,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Trend',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: SfCartesianChart(
                          primaryXAxis: CategoryAxis(),
                          series: [
                            LineSeries<MonthlyData, String>(
                              dataSource: analytics.monthlyTrend,
                              xValueMapper: (datum, _) => datum.month,
                              yValueMapper: (datum, _) => datum.count,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}