import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';

class ResellerAnalyticsScreen extends StatefulWidget {
  const ResellerAnalyticsScreen({super.key});

  @override
  State<ResellerAnalyticsScreen> createState() => _ResellerAnalyticsScreenState();
}

class _ResellerAnalyticsScreenState extends State<ResellerAnalyticsScreen> {
  int _totalDealers = 0;
  int _activeKeys = 0;
  int _soldKeys = 0;
  double _totalRevenue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _totalDealers = 12;
      _activeKeys = 150;
      _soldKeys = 48;
      _totalRevenue = 24000.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildRevenueChart(),
            const SizedBox(height: 24),
            _buildDealerGrowthChart(),
            const SizedBox(height: 24),
            _buildKeyStatusChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Dealers',
                _totalDealers.toString(),
                Icons.store,
                AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Active Keys',
                _activeKeys.toString(),
                Icons.vpn_key,
                AppTheme.successColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Sold Keys',
                _soldKeys.toString(),
                Icons.sell,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Revenue',
                'BDT ${_totalRevenue.toStringAsFixed(0)}',
                Icons.attach_money,
                AppTheme.accentColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueChart() {
    final data = [
      SalesData('Jan', 15000),
      SalesData('Feb', 18000),
      SalesData('Mar', 22000),
      SalesData('Apr', 24000),
      SalesData('May', 20000),
      SalesData('Jun', 28000),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue Trend',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(),
                series: <ChartSeries>[
                  LineSeries<SalesData, String>(
                    dataSource: data,
                    xValueMapper: (SalesData d, _) => d.month,
                    yValueMapper: (SalesData d, _) => d.sales,
                    color: AppTheme.primaryColor,
                    width: 3,
                    markerSettings: const MarkerSettings(isVisible: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDealerGrowthChart() {
    final data = [
      SalesData('Jan', 5),
      SalesData('Feb', 8),
      SalesData('Mar', 10),
      SalesData('Apr', 12),
      SalesData('May', 12),
      SalesData('Jun', 15),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dealer Growth',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(),
                series: <ChartSeries>[
                  ColumnSeries<SalesData, String>(
                    dataSource: data,
                    xValueMapper: (SalesData d, _) => d.month,
                    yValueMapper: (SalesData d, _) => d.sales,
                    color: AppTheme.successColor,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyStatusChart() {
    final data = [
      KeyStatusData('Available', 150, AppTheme.successColor),
      KeyStatusData('Sold', 48, Colors.orange),
      KeyStatusData('Activated', 200, AppTheme.primaryColor),
      KeyStatusData('Revoked', 2, AppTheme.errorColor),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Key Distribution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfCartesianChart(
                primaryXAxis: CategoryAxis(),
                primaryYAxis: NumericAxis(),
                series: <ChartSeries>[
                  BarSeries<KeyStatusData, String>(
                    dataSource: data,
                    xValueMapper: (KeyStatusData d, _) => d.label,
                    yValueMapper: (KeyStatusData d, _) => d.value,
                    pointColorMapper: (KeyStatusData d, _) => d.color,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesData {
  final String month;
  final double sales;

  SalesData(this.month, this.sales);
}

class KeyStatusData {
  final String label;
  final int value;
  final Color color;

  KeyStatusData(this.label, this.value, this.color);
}