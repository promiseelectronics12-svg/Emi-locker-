import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../shared/api/analytics_repository.dart';
import '../../../shared/models/analytics.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';

class DealerAnalyticsScreen extends StatefulWidget {
  const DealerAnalyticsScreen({super.key});

  @override
  State<DealerAnalyticsScreen> createState() => _DealerAnalyticsScreenState();
}

class _DealerAnalyticsScreenState extends State<DealerAnalyticsScreen> {
  DealerAnalytics? _analytics;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final analytics =
          await context.read<AnalyticsRepository>().getDealerAnalytics();
      setState(() {
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            onPressed: _loadAnalytics,
            icon: const Icon(Icons.refresh),
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
      return EmptyStateWidget(
        icon: Icons.error_outline,
        title: 'Failed to load analytics',
        subtitle: _error,
        action: ElevatedButton(
          onPressed: _loadAnalytics,
          child: const Text('Retry'),
        ),
      );
    }

    if (_analytics == null) {
      return const EmptyStateWidget(
        icon: Icons.analytics,
        title: 'No data available',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnalytics,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 16),
            _buildStatusChart(),
            const SizedBox(height: 16),
            _buildMonthlyTrendChart(),
            const SizedBox(height: 16),
            _buildNeirExportCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Devices',
                _analytics!.totalDevices.toString(),
                Icons.phone_android,
                AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Active',
                _analytics!.activeDevices.toString(),
                Icons.check_circle,
                AppTheme.successColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'EMI Collected',
                '${_analytics!.totalEmiCollected.toStringAsFixed(0)} BDT',
                Icons.attach_money,
                AppTheme.secondaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'EMI Pending',
                '${_analytics!.totalEmiPending.toStringAsFixed(0)} BDT',
                Icons.pending,
                AppTheme.warningColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
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
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChart() {
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
                series: <PieSeries<DeviceStatusCount, String>>[
                  PieSeries<DeviceStatusCount, String>(
                    dataSource: _analytics!.statusBreakdown,
                    xValueMapper: (DeviceStatusCount data, _) => data.status,
                    yValueMapper: (DeviceStatusCount data, _) => data.count,
                    dataLabelMapper: (DeviceStatusCount data, _) =>
                        '${data.status}: ${data.count}',
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartDataLabelPosition.outside,
                    ),
                  ),
                ],
                palette: const [
                  AppTheme.successColor,
                  AppTheme.errorColor,
                  AppTheme.warningColor,
                  Colors.grey,
                  AppTheme.primaryColor,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyTrendChart() {
    if (_analytics!.monthlyTrend.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Collection Trend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(
                  labelRotation: -45,
                ),
                series: <ChartSeries<MonthlyData, String>>[
                  LineSeries<MonthlyData, String>(
                    dataSource: _analytics!.monthlyTrend,
                    xValueMapper: (MonthlyData data, _) =>
                        '${data.month.substring(0, 3)} ${data.year}',
                    yValueMapper: (MonthlyData data, _) => data.collected,
                    name: 'Collection',
                    color: AppTheme.primaryColor,
                    width: 2,
                    markerSettings: const MarkerSettings(
                      isVisible: true,
                      shape: DataMarkerType.circle,
                    ),
                  ),
                ],
                axes: const [
                  NumericAxis(
                    name: 'yAxis',
                    labelFormat: '{value} BDT',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeirExportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEIR Export',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Generate Excel file for BTRC submission with all enrolled device IMEIs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await context
                        .read<AnalyticsRepository>()
                        .shareNeirExcel();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('NEIR export generated'),
                          backgroundColor: AppTheme.successColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Export failed: $e'),
                          backgroundColor: AppTheme.errorColor,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Generate & Share NEIR Excel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}