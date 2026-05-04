import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class AnalyticsDashboard extends StatelessWidget {
  const AnalyticsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final List<ChartData> data = [
      ChartData('Active', 120, Colors.green),
      ChartData('Locked', 15, Colors.red),
      ChartData('Overdue', 25, Colors.orange),
      ChartData('Decoupled', 40, Colors.blue),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('Device Status Distribution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SfCircularChart(
                    legend: Legend(isVisible: true),
                    series: <CircularSeries>[
                      PieSeries<ChartData, String>(
                        dataSource: data,
                        xValueMapper: (ChartData data, _) => data.status,
                        yValueMapper: (ChartData data, _) => data.count,
                        pointColorMapper: (ChartData data, _) => data.color,
                        dataLabelSettings: const DataLabelSettings(isVisible: true),
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text('EMI Collection Trend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SfCartesianChart(
                    primaryXAxis: CategoryAxis(),
                    series: <CartesianSeries>[
                      ColumnSeries<SalesData, String>(
                        dataSource: [
                          SalesData('Jan', 35),
                          SalesData('Feb', 28),
                          SalesData('Mar', 34),
                          SalesData('Apr', 32),
                          SalesData('May', 40),
                        ],
                        xValueMapper: (SalesData sales, _) => sales.month,
                        yValueMapper: (SalesData sales, _) => sales.sales,
                        color: Colors.blue,
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChartData {
  ChartData(this.status, this.count, this.color);
  final String status;
  final double count;
  final Color color;
}

class SalesData {
  SalesData(this.month, this.sales);
  final String month;
  final double sales;
}
