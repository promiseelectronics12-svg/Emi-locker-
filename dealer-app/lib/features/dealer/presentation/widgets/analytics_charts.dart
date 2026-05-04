import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../shared/models/dealer_analytics_model.dart';
import '../../shared/theme/app_theme.dart';

class CollectionRateChart extends StatelessWidget {
  final CollectionRate data;

  const CollectionRateChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Collection Rate',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'EMI payment on time this month vs last month',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x : point.y%',
                ),
                primaryXAxis: CategoryAxis(
                  title: AxisTitle(text: 'Month'),
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: 'Collection Rate %'),
                  minimum: 0,
                  maximum: 100,
                  interval: 20,
                ),
                series: <BarSeries<ChartSampleData, String>>[
                  BarSeries<ChartSampleData, String>(
                    dataSource: [
                      ChartSampleData(
                        x: 'Last Month',
                        y: data.lastMonthRate,
                      ),
                      ChartSampleData(
                        x: 'This Month',
                        y: data.thisMonthRate,
                      ),
                    ],
                    xValueMapper: (ChartSampleData data, _) => data.x,
                    yValueMapper: (ChartSampleData data, _) => data.y,
                    color: AppTheme.primaryColor,
                    width: 0.5,
                    spacing: 0.3,
                  ),
                ],
                chartArea: const ChartAreaAreaBorderProps(
                  border: BorderSide(color: Colors.transparent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RateIndicator(
                  label: 'Last Month',
                  rate: data.lastMonthRate,
                  paid: data.lastMonthPaid,
                  total: data.lastMonthTotal,
                ),
                _RateIndicator(
                  label: 'This Month',
                  rate: data.thisMonthRate,
                  paid: data.thisMonthPaid,
                  total: data.thisMonthTotal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RateIndicator extends StatelessWidget {
  final String label;
  final double rate;
  final int paid;
  final int total;

  const _RateIndicator({
    required this.label,
    required this.rate,
    required this.paid,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final color = rate >= 80 ? AppTheme.successColor : (rate >= 50 ? AppTheme.warningColor : AppTheme.errorColor);

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${rate.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          '$paid / $total EMIs',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}

class OverdueAgingChart extends StatelessWidget {
  final List<OverdueAgingBucket> data;

  const OverdueAgingChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overdue Aging Report',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Devices by days overdue',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            if (data.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No overdue devices'),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: SfBarChart(
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : point.y devices',
                  ),
                  primaryXAxis: CategoryAxis(
                    title: AxisTitle(text: 'Days Overdue'),
                  ),
                  primaryYAxis: NumericAxis(
                    title: AxisTitle(text: 'Number of Devices'),
                    minimum: 0,
                    interval: 1,
                  ),
                  series: <BarSeries<ChartSampleData, String>>[
                    BarSeries<ChartSampleData, String>(
                      dataSource: data
                          .map((e) => ChartSampleData(
                                x: e.label,
                                y: e.count.toDouble(),
                              ))
                          .toList(),
                      xValueMapper: (ChartSampleData data, _) => data.x,
                      yValueMapper: (ChartSampleData data, _) => data.y,
                      color: AppTheme.warningColor,
                      width: 0.5,
                    ),
                  ],
                  chartArea: const ChartAreaAreaBorderProps(
                    border: BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: data
                  .map((e) => _AgingLegendItem(
                        label: e.label,
                        count: e.count,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgingLegendItem extends StatelessWidget {
  final String label;
  final int count;

  const _AgingLegendItem({
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppTheme.warningColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $count',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }
}

class DeviceStatusPieChart extends StatelessWidget {
  final List<DeviceStatusBreakdown> data;

  const DeviceStatusPieChart({super.key, required this.data});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppTheme.successColor;
      case 'locked':
        return AppTheme.errorColor;
      case 'grace_period':
        return AppTheme.warningColor;
      case 'decoupling':
        return Colors.orange;
      case 'decoupled':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = data.fold<int>(0, (sum, item) => sum + item.count);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Status Breakdown',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current status of all enrolled devices',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            if (data.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No devices enrolled'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 180,
                      child: SfPieChart(
                        tooltipBehavior: TooltipBehavior(
                          enable: true,
                          format: 'point.x : point.y (point.sum%)',
                        ),
                        series: PieSeries<DeviceStatusBreakdown, String>(
                          dataSource: data,
                          xValueMapper: (DeviceStatusBreakdown data, _) => _formatStatus(data.status),
                          yValueMapper: (DeviceStatusBreakdown data, _) => data.count,
                          pointColorMapper: (DeviceStatusBreakdown data, _) => _getStatusColor(data.status),
                          dataLabelSettings: const DataLabelSettings(
                            isVisible: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: data.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              color: _getStatusColor(e.status),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_formatStatus(e.status)}: ${e.count}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            const Divider(),
            Text(
              'Total Devices: $total',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    return status.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}

class RevenueReportChart extends StatelessWidget {
  final RevenueReport data;

  const RevenueReportChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Report',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Expected EMI income vs collected',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  format: 'point.x : BDT point.y',
                ),
                legend: Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                ),
                primaryXAxis: CategoryAxis(
                  title: AxisTitle(text: 'Month'),
                ),
                primaryYAxis: NumericAxis(
                  title: AxisTitle(text: 'Amount (BDT)'),
                  labelFormat: 'BDT {value}',
                ),
                series: <BarSeries<ChartSampleData, String>>[
                  BarSeries<ChartSampleData, String>(
                    dataSource: [
                      ChartSampleData(
                        x: 'Last Month\nExpected',
                        y: data.expectedLastMonth,
                      ),
                      ChartSampleData(
                        x: 'Last Month\nCollected',
                        y: data.collectedLastMonth,
                      ),
                      ChartSampleData(
                        x: 'This Month\nExpected',
                        y: data.expectedThisMonth,
                      ),
                      ChartSampleData(
                        x: 'This Month\nCollected',
                        y: data.collectedThisMonth,
                      ),
                    ],
                    xValueMapper: (ChartSampleData data, _) => data.x,
                    yValueMapper: (ChartSampleData data, _) => data.y,
                    color: AppTheme.primaryColor,
                    width: 0.5,
                    spacing: 0.2,
                  ),
                ],
                chartArea: const ChartAreaAreaBorderProps(
                  border: BorderSide(color: Colors.transparent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RevenueIndicator(
                  label: 'This Month Collected',
                  amount: data.collectedThisMonth,
                  expected: data.expectedThisMonth,
                ),
                _RevenueIndicator(
                  label: 'Collection Rate',
                  amount: data.collectionRateThisMonth,
                  isPercentage: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueIndicator extends StatelessWidget {
  final String label;
  final double amount;
  final double? expected;
  final bool isPercentage;

  const _RevenueIndicator({
    required this.label,
    required this.amount,
    this.expected,
    this.isPercentage = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isPercentage ? '${amount.toStringAsFixed(1)}%' : 'BDT ${_formatAmount(amount)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (expected != null)
          Text(
            'of BDT ${_formatAmount(expected!)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
            ),
          ),
      ],
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}

class KeyUsageChart extends StatelessWidget {
  final KeyUsageReport data;

  const KeyUsageChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key Usage',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Activation keys purchased vs used vs available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            if (data.totalPurchased == 0)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No keys purchased yet'),
                ),
              )
            else
              SizedBox(
                height: 200,
                child: SfBarChart(
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    format: 'point.x : point.y keys',
                  ),
                  legend: Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                  ),
                  primaryXAxis: CategoryAxis(
                    title: AxisTitle(text: 'Key Status'),
                  ),
                  primaryYAxis: NumericAxis(
                    title: AxisTitle(text: 'Number of Keys'),
                    minimum: 0,
                    interval: 1,
                  ),
                  series: <BarSeries<ChartSampleData, String>>[
                    BarSeries<ChartSampleData, String>(
                      dataSource: [
                        ChartSampleData(
                          x: 'Purchased',
                          y: data.totalPurchased.toDouble(),
                        ),
                        ChartSampleData(
                          x: 'Used',
                          y: data.used.toDouble(),
                        ),
                        ChartSampleData(
                          x: 'Available',
                          y: data.available.toDouble(),
                        ),
                      ],
                      xValueMapper: (ChartSampleData data, _) => data.x,
                      yValueMapper: (ChartSampleData data, _) => data.y,
                      color: AppTheme.secondaryColor,
                      width: 0.5,
                      spacing: 0.3,
                    ),
                  ],
                  chartArea: const ChartAreaAreaBorderProps(
                    border: BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _KeyUsageIndicator(
                  label: 'Purchased',
                  count: data.totalPurchased,
                  color: AppTheme.primaryColor,
                ),
                _KeyUsageIndicator(
                  label: 'Used',
                  count: data.used,
                  color: AppTheme.successColor,
                ),
                _KeyUsageIndicator(
                  label: 'Available',
                  count: data.available,
                  color: AppTheme.secondaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyUsageIndicator extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _KeyUsageIndicator({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class ChartSampleData {
  final String x;
  final double y;

  ChartSampleData({required this.x, required this.y});
}