import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/di/injection.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _analytics;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    try {
      final response = await Injection.apiClient.get(
        '/api/v1/dealer/analytics',
      );
      setState(() {
        _analytics = response.data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _analytics == null
          ? const Center(child: Text('No analytics data available'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildDeviceStatusChart(),
                const SizedBox(height: 24),
                _buildMonthlyEnrollmentsChart(),
                const SizedBox(height: 24),
                _buildEmiCollectionCard(),
              ],
            ),
    );
  }

  Widget _buildDeviceStatusChart() {
    final statusData = _analytics!['device_status'] ?? {};
    final chartData = [
      _ChartData(
        'Active',
        (statusData['active'] ?? 0).toDouble(),
        const Color(0xFF34A853),
      ),
      _ChartData(
        'Locked',
        (statusData['locked'] ?? 0).toDouble(),
        const Color(0xFFEA4335),
      ),
      _ChartData(
        'Pending',
        (statusData['pending'] ?? 0).toDouble(),
        const Color(0xFFFBBC04),
      ),
      _ChartData(
        'Decoupled',
        (statusData['decoupled'] ?? 0).toDouble(),
        const Color(0xFF9E9E9E),
      ),
    ];

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
              height: 250,
              child: SfCircularChart(
                legend: const Legend(
                  isVisible: true,
                  position: LegendPosition.bottom,
                ),
                series: <CircularSeries>[
                  PieSeries<_ChartData, String>(
                    dataSource: chartData,
                    xValueMapper: (d, _) => d.label,
                    yValueMapper: (d, _) => d.value,
                    pointColorMapper: (d, _) => d.color,
                    dataLabelSettings: const DataLabelSettings(isVisible: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyEnrollmentsChart() {
    final monthlyData = _analytics!['monthly_enrollments'] as List? ?? [];
    final chartData = monthlyData.map((e) {
      return _ChartData(
        e['month'] ?? '',
        (e['count'] ?? 0).toDouble(),
        const Color(0xFF1A73E8),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly Enrollments',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: SfCartesianChart(
                primaryXAxis: const CategoryAxis(),
                primaryYAxis: const NumericAxis(),
                series: <CartesianSeries>[
                  ColumnSeries<_ChartData, String>(
                    dataSource: chartData,
                    xValueMapper: (d, _) => d.label,
                    yValueMapper: (d, _) => d.value,
                    color: const Color(0xFF1A73E8),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
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

  Widget _buildEmiCollectionCard() {
    final collectionRate = _analytics!['emi_collection_rate'] ?? 0;
    final totalCollected = _analytics!['total_collected'] ?? 0;
    final totalExpected = _analytics!['total_expected'] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EMI Collection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value:
                  (collectionRate is num ? collectionRate.toDouble() : 0) / 100,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                collectionRate > 80
                    ? Colors.green
                    : collectionRate > 50
                    ? Colors.orange
                    : Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Collection Rate: $collectionRate%'),
                Text('৳$totalCollected / ৳$totalExpected'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartData {
  final String label;
  final double value;
  final Color color;

  _ChartData(this.label, this.value, this.color);
}
