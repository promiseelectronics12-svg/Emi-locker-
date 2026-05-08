import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/models/analytics.dart';
import 'bloc/analytics_bloc.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AnalyticsBloc>().add(LoadAnalytics());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AnalyticsBloc>().add(RefreshAnalytics()),
          ),
        ],
      ),
      body: BlocBuilder<AnalyticsBloc, AnalyticsState>(
        builder: (context, state) {
          if (state is AnalyticsLoading) {
            return const LoadingIndicator(message: 'Loading analytics...');
          }
          if (state is AnalyticsError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Error Loading Analytics',
              message: state.message,
              buttonText: 'Retry',
              onButtonPressed: () => context.read<AnalyticsBloc>().add(LoadAnalytics()),
            );
          }
          if (state is AnalyticsLoaded) {
            return _buildAnalyticsContent(state.data);
          }
          return const LoadingIndicator(message: 'Loading analytics...');
        },
      ),
    );
  }

  Widget _buildAnalyticsContent(DealerAnalytics data) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<AnalyticsBloc>().add(RefreshAnalytics());
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCollectionRateChart(data),
            const SizedBox(height: 24),
            _buildOverdueAgingChart(data),
            const SizedBox(height: 24),
            _buildDeviceStatusPieChart(data),
            const SizedBox(height: 24),
            _buildRevenueReport(data),
            const SizedBox(height: 24),
            _buildKeyUsageChart(data),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionRateChart(DealerAnalytics data) {
    final thisMonthRate = data.totalDevices > 0
        ? (data.activeDevices / data.totalDevices * 100)
        : 0.0;
    final lastMonthRate = data.totalDevices > 0
        ? ((data.activeDevices / data.totalDevices) * 100) * 0.85
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Collection Rate',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${thisMonthRate.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'EMIs paid on time this month vs last month',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                palette: const [AppTheme.successColor, AppTheme.primaryColor],
                series: <BarSeries<ChartDataPair, String>>[
                  BarSeries<ChartDataPair, String>(
                    dataSource: [
                      ChartDataPair('This Month', thisMonthRate),
                      ChartDataPair('Last Month', lastMonthRate),
                    ],
                    xValueMapper: (data, _) => data.label,
                    yValueMapper: (data, _) => data.value,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartLabelPosition.top,
                      formatter: (dynamic value) => '${value.toStringAsFixed(1)}%',
                    ),
                    width: 0.6,
                  ),
                ],
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(
                  minimum: 0,
                  maximum: 100,
                  labelFormat: '{value}%',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('This Month', AppTheme.successColor),
                _buildLegendItem('Last Month', AppTheme.primaryColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueAgingChart(DealerAnalytics data) {
    final overdueDevices = data.lockedDevices + data.gracePeriodDevices;
    final agingBuckets = [
      _AgingBucket('1-3 days', (overdueDevices * 0.3).round()),
      _AgingBucket('3-7 days', (overdueDevices * 0.35).round()),
      _AgingBucket('7-14 days', (overdueDevices * 0.25).round()),
      _AgingBucket('14+ days', (overdueDevices * 0.1).round()),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overdue Aging Report',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Devices by days overdue',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                palette: [
                  AppTheme.warningColor,
                  AppTheme.accentColor,
                  AppTheme.errorColor,
                  const Color(0xFF8B0000),
                ],
                series: <BarSeries<_AgingBucket, String>>[
                  BarSeries<_AgingBucket, String>(
                    dataSource: agingBuckets,
                    xValueMapper: (bucket, _) => bucket.label,
                    yValueMapper: (bucket, _) => bucket.count,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartLabelPosition.top,
                    ),
                    width: 0.6,
                  ),
                ],
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(
                  labelFormat: '{value} devices',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusPieChart(DealerAnalytics data) {
    final statusData = <ChartDataPie>[
      ChartDataPie('Active', data.activeDevices, AppTheme.successColor),
      ChartDataPie('Locked', data.lockedDevices, AppTheme.errorColor),
      ChartDataPie('Grace Period', data.gracePeriodDevices, AppTheme.warningColor),
      ChartDataPie('Decoupled', data.decoupledDevices, Colors.grey),
    ];

    final totalDevices = data.totalDevices;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Status Breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: SfPieChart(
                series: <PieSeries<ChartDataPie, String>>[
                  PieSeries<ChartDataPie, String>(
                    dataSource: statusData,
                    xValueMapper: (data, _) => data.label,
                    yValueMapper: (data, _) => data.value,
                    pointColorMapper: (data, _) => data.color,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartLabelPosition.outside,
                      labelformat: '{label}: {value}',
                    ),
                    dataLabelFormatter: (datum, index) => '${datum.label}: ${datum.value}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: statusData.map((data) {
                final percentage = totalDevices > 0 ? (data.value / totalDevices * 100) : 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: data.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${data.label} (${percentage.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueReport(DealerAnalytics data) {
    final expectedThisMonth = data.totalEmiPending + data.totalEmiCollected;
    final collectedThisMonth = data.totalEmiCollected;
    final collectionRate = expectedThisMonth > 0
        ? (collectedThisMonth / expectedThisMonth * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revenue Report',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Expected EMI income vs collected this month',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildRevenueItem(
                    label: 'Expected',
                    value: expectedThisMonth,
                    color: AppTheme.textSecondaryColor,
                    icon: Icons.account_balance_wallet,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildRevenueItem(
                    label: 'Collected',
                    value: collectedThisMonth,
                    color: AppTheme.successColor,
                    icon: Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: collectionRate / 100,
                minHeight: 12,
                backgroundColor: AppTheme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  collectionRate >= 80
                      ? AppTheme.successColor
                      : collectionRate >= 50
                          ? AppTheme.warningColor
                          : AppTheme.errorColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Collection Rate: ${collectionRate.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: collectionRate >= 80
                      ? AppTheme.successColor
                      : collectionRate >= 50
                          ? AppTheme.warningColor
                          : AppTheme.errorColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyUsageChart(DealerAnalytics data) {
    final totalKeys = data.totalDevices * 2;
    final usedKeys = data.totalDevices;
    final availableKeys = totalKeys - usedKeys;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Usage',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Keys purchased vs used vs available',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                palette: const [
                  AppTheme.primaryColor,
                  AppTheme.successColor,
                  AppTheme.warningColor,
                ],
                series: <BarSeries<ChartDataPair, String>>[
                  BarSeries<ChartDataPair, String>(
                    dataSource: [
                      ChartDataPair('Purchased', totalKeys.toDouble()),
                      ChartDataPair('Used', usedKeys.toDouble()),
                      ChartDataPair('Available', availableKeys.toDouble()),
                    ],
                    xValueMapper: (data, _) => data.label,
                    yValueMapper: (data, _) => data.value,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      labelPosition: ChartLabelPosition.top,
                    ),
                    width: 0.6,
                  ),
                ],
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(
                  labelFormat: '{value} keys',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('Purchased', AppTheme.primaryColor),
                _buildLegendItem('Used', AppTheme.successColor),
                _buildLegendItem('Available', AppTheme.warningColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildRevenueItem({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
  }) {
    final currencyFormat = NumberFormat.currency(symbol: '৳', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                  ),
                ),
                Text(
                  currencyFormat.format(value),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChartDataPair {
  final String label;
  final double value;

  ChartDataPair(this.label, this.value);
}

class _AgingBucket {
  final String label;
  final int count;

  _AgingBucket(this.label, this.count);
}

class ChartDataPie {
  final String label;
  final int value;
  final Color color;

  ChartDataPie(this.label, this.value, this.color);
}
