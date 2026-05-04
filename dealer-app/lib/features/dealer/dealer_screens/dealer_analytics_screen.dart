import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../shared/api/api_client.dart';
import '../../shared/theme/app_theme.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class DealerAnalyticsScreen extends StatefulWidget {
  const DealerAnalyticsScreen({super.key});

  @override
  State<DealerAnalyticsScreen> createState() => _DealerAnalyticsScreenState();
}

class _DealerAnalyticsScreenState extends State<DealerAnalyticsScreen> {
  Map<String, dynamic>? _analyticsData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/analytics/dealer',
          queryParameters: {'dealer_id': authState.user!.id},
        );
        setState(() {
          _analyticsData = response.data as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load analytics: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _analyticsData == null
              ? const Center(child: Text('No analytics data available'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOverviewCards(),
                      const SizedBox(height: 24),
                      _buildRevenueChart(),
                      const SizedBox(height: 24),
                      _buildDeviceStatusChart(),
                      const SizedBox(height: 24),
                      _buildPaymentTimeline(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOverviewCards() {
    final data = _analyticsData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OverviewCard(
                title: 'Total Revenue',
                value: '৳${(data['total_revenue'] ?? 0).toStringAsFixed(0)}',
                icon: Icons.attach_money,
                color: AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OverviewCard(
                title: 'Total Devices',
                value: '${data['total_devices'] ?? 0}',
                icon: Icons.phonelink_lock,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OverviewCard(
                title: 'Active Devices',
                value: '${data['active_devices'] ?? 0}',
                icon: Icons.check_circle,
                color: AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OverviewCard(
                title: 'Locked Devices',
                value: '${data['locked_devices'] ?? 0}',
                icon: Icons.lock,
                color: AppTheme.errorColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OverviewCard(
                title: 'Overdue Payments',
                value: '${data['overdue_payments'] ?? 0}',
                icon: Icons.warning,
                color: AppTheme.warningColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OverviewCard(
                title: 'This Month',
                value: '৳${(data['this_month_revenue'] ?? 0).toStringAsFixed(0)}',
                icon: Icons.calendar_today,
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRevenueChart() {
    final revenueData = _analyticsData?['monthly_revenue'] as List<dynamic>? ?? [];

    if (revenueData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Trend',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(
                  labelFormat: '৳{value}',
                ),
                series: <ChartSeries>[
                  LineSeries<ChartData, String>(
                    dataSource: revenueData.map((item) {
                      return ChartData(
                        item['month'] as String,
                        (item['revenue'] as num).toDouble(),
                      );
                    }).toList(),
                    xValueMapper: (ChartData data, _) => data.label,
                    yValueMapper: (ChartData data, _) => data.value,
                    color: AppTheme.primaryColor,
                    width: 3,
                    markerSettings: const MarkerSettings(
                      isVisible: true,
                      shape: DataMarkerType.circle,
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

  Widget _buildDeviceStatusChart() {
    final statusData = _analyticsData?['device_status'] as Map<String, dynamic>? ?? {};

    if (statusData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Status Distribution',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfPieChart(
                series: <ChartSeries>[
                  PieSeries<MapEntry<String, int>, String>(
                    dataSource: statusData.entries.map((entry) {
                      return MapEntry(entry.key, entry.value as int);
                    }).toList(),
                    xValueMapper: (entry, _) => entry.key,
                    yValueMapper: (entry, _) => entry.value,
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

  Widget _buildPaymentTimeline() {
    final payments = _analyticsData?['upcoming_payments'] as List<dynamic>? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upcoming Payments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (payments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text('No upcoming payments'),
                ),
              )
            else
              ...payments.take(5).map((payment) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.payment,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  title: Text(payment['customer_name'] as String),
                  subtitle: Text('Due: ${payment['due_date']}'),
                  trailing: Text(
                    '৳${(payment['amount'] as num).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _OverviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  final String label;
  final double value;

  ChartData(this.label, this.value);
}