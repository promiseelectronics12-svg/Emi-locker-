import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/device.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final ApiClient _apiClient = ApiClient();

  List<Device> _devices = [];
  bool _isLoading = true;
  String? _error;

  int get _totalDevices => _devices.length;
  int get _activeDevices =>
      _devices.where((d) => d.status == DeviceStatus.active).length;
  int get _lockedDevices =>
      _devices.where((d) => d.status == DeviceStatus.locked).length;
  int get _overdueDevices =>
      _devices.where((d) => d.isPaymentOverdue).length;

  double get _totalReceivable => _devices.fold(
      0, (sum, d) => sum + (d.totalAmount - d.paidAmount));
  double get _totalCollected =>
      _devices.fold(0, (sum, d) => sum + d.paidAmount);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/devices');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['devices'] as List<dynamic>;
        setState(() {
          _devices = data
              .map((json) => Device.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load analytics data';
      });
    } finally {
      setState(() {
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCards(),
                        const SizedBox(height: 24),
                        _buildStatusChart(),
                        const SizedBox(height: 24),
                        _buildPaymentProgressChart(),
                        const SizedBox(height: 24),
                        _buildOverdueList(),
                      ],
                    ),
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
                _totalDevices.toString(),
                AppTheme.primaryColor,
                Icons.devices,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Active',
                _activeDevices.toString(),
                AppTheme.successColor,
                Icons.check_circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Locked',
                _lockedDevices.toString(),
                AppTheme.errorColor,
                Icons.lock,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Overdue',
                _overdueDevices.toString(),
                AppTheme.warningColor,
                Icons.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Collected',
                '৳${_totalCollected.toStringAsFixed(0)}',
                AppTheme.successColor,
                Icons.attach_money,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Receivable',
                '৳${_totalReceivable.toStringAsFixed(0)}',
                AppTheme.warningColor,
                Icons.account_balance_wallet,
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
    Color color,
    IconData icon,
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
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
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

  Widget _buildStatusChart() {
    if (_devices.isEmpty) {
      return const SizedBox.shrink();
    }

    final statusData = [
      _ChartData('Active', _activeDevices),
      _ChartData('Locked', _lockedDevices),
      _ChartData('Grace', _devices.where((d) => d.status == DeviceStatus.gracePeriod).length),
      _ChartData('Pending', _devices.where((d) => d.status == DeviceStatus.pendingDecouple).length),
      _ChartData('Decoupled', _devices.where((d) => d.status == DeviceStatus.decoupled).length),
    ].where((d) => d.y > 0).toList();

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
                series: PieChartSeries(
                  dataSource: statusData,
                  xValueMapper: (data, _) => data.x,
                  yValueMapper: (data, _) => data.y,
                  dataLabelMapper: (data, _) => '${data.x}: ${data.y}',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentProgressChart() {
    if (_devices.isEmpty) {
      return const SizedBox.shrink();
    }

    final ranges = <String, int>{
      '0-25%': 0,
      '26-50%': 0,
      '51-75%': 0,
      '76-99%': 0,
      '100%': 0,
    };

    for (final device in _devices) {
      final progress = device.paymentProgress;
      if (progress <= 25) {
        ranges['0-25%'] = ranges['0-25%']! + 1;
      } else if (progress <= 50) {
        ranges['26-50%'] = ranges['26-50%']! + 1;
      } else if (progress <= 75) {
        ranges['51-75%'] = ranges['51-75%']! + 1;
      } else if (progress < 100) {
        ranges['76-99%'] = ranges['76-99%']! + 1;
      } else {
        ranges['100%'] = ranges['100%']! + 1;
      }
    }

    final chartData = ranges.entries
        .map((e) => _ChartData(e.key, e.value))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Progress Distribution',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: SfBarChart(
                series: <ChartSeries>[
                  BarSeries<_ChartData, String>(
                    dataSource: chartData,
                    xValueMapper: (data, _) => data.x,
                    yValueMapper: (data, _) => data.y,
                  ),
                ],
                primaryXAxis: CategoryAxis(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverdueList() {
    final overdueDevices =
        _devices.where((d) => d.isPaymentOverdue).toList();

    if (overdueDevices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_outlined,
                  color: AppTheme.errorColor,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Overdue Payments',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${overdueDevices.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...overdueDevices.take(5).map((device) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.customerName),
                subtitle: Text(
                  'Overdue by ${-device.daysUntilNextPayment} days',
                ),
                trailing: Text(
                  '৳${device.emiAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.errorColor,
                  ),
                ),
              );
            }),
            if (overdueDevices.length > 5)
              TextButton(
                onPressed: () {
                },
                child: Text('View all ${overdueDevices.length} overdue'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartData {
  final String x;
  final int y;

  _ChartData(this.x, this.y);
}