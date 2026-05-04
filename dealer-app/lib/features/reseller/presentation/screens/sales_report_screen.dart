import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPeriod = 'This Month';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Report'),
        backgroundColor: AppTheme.resellerColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Period',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('This Week'),
                          selected: _selectedPeriod == 'This Week',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPeriod = 'This Week';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('This Month'),
                          selected: _selectedPeriod == 'This Month',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPeriod = 'This Month';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('This Quarter'),
                          selected: _selectedPeriod == 'This Quarter',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPeriod = 'This Quarter';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('This Year'),
                          selected: _selectedPeriod == 'This Year',
                          onSelected: (selected) {
                            setState(() {
                              _selectedPeriod = 'This Year';
                            });
                          },
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
                    const Text(
                      'Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryItem(
                            label: 'Keys Sold',
                            value: '0',
                            icon: Icons.vpn_key,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        Expanded(
                          child: _SummaryItem(
                            label: 'Revenue',
                            value: '৳0',
                            icon: Icons.attach_money,
                            color: AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: _SummaryItem(
                            label: 'Active Dealers',
                            value: '0',
                            icon: Icons.store,
                            color: AppTheme.resellerColor,
                          ),
                        ),
                        Expanded(
                          child: _SummaryItem(
                            label: 'Avg. Price/Key',
                            value: '৳0',
                            icon: Icons.trending_up,
                            color: Colors.orange,
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
                    const Text(
                      'Recent Sales',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'No sales yet',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.file_download),
              label: const Text('Export Report'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
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