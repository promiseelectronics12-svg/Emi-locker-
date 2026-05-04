import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../bloc/auth_bloc.dart';

class ResellerAnalyticsScreen extends StatefulWidget {
  const ResellerAnalyticsScreen({super.key});

  @override
  State<ResellerAnalyticsScreen> createState() =>
      _ResellerAnalyticsScreenState();
}

class _ResellerAnalyticsScreenState extends State<ResellerAnalyticsScreen> {
  final ApiClient _apiClient = ApiClient();
  Map<String, dynamic>? _analytics;
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
      if (authState is! AuthAuthenticated) return;

      final response = await _apiClient.get(
        '/reseller/analytics',
        queryParameters: {'reseller_id': authState.user.resellerId},
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _analytics = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: _isLoading
          ? const LoadingWidget(message: 'Loading analytics...')
          : _analytics == null
              ? const ErrorDisplayWidget(message: 'Failed to load analytics')
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final data = _analytics!;
    final totalDealers = data['total_dealers'] as int? ?? 0;
    final totalDevices = data['total_devices'] as int? ?? 0;
    final totalKeys = data['total_keys'] as int? ?? 0;
    final usedKeys = data['used_keys'] as int? ?? 0;
    final totalCollection = (data['total_collection'] as num?)?.toDouble() ?? 0;

    final dealerGrowth = (data['dealer_growth'] as List<dynamic>?)
            ?.map((e) => ChartData(
                  label: e['month'] as String,
                  value: (e['count'] as num?)?.toDouble() ?? 0,
                ))
            .toList() ??
        [];

    final deviceGrowth = (data['device_growth'] as List<dynamic>?)
            ?.map((e) => ChartData(
                  label: e['month'] as String,
                  value: (e['count'] as num?)?.toDouble() ?? 0,
                ))
            .toList() ??
        [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCards(
            totalDealers,
            totalDevices,
            totalKeys,
            usedKeys,
            totalCollection,
          ),
          const SizedBox(height: 24),
          if (dealerGrowth.isNotEmpty)
            AnalyticsChart(
              data: dealerGrowth,
              title: 'Dealer Growth (Last 6 Months)',
            ),
          const SizedBox(height: 16),
          if (deviceGrowth.isNotEmpty)
            AnalyticsChart(
              data: deviceGrowth,
              title: 'Device Growth (Last 6 Months)',
            ),
          const SizedBox(height: 16),
          _buildTopDealers(data),
        ],
      ),
    );
  }

  Widget _buildOverviewCards(
    int totalDealers,
    int totalDevices,
    int totalKeys,
    int usedKeys,
    double totalCollection,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _StatCard(
          title: 'Total Dealers',
          value: totalDealers.toString(),
          icon: Icons.store,
          color: Colors.blue,
        ),
        _StatCard(
          title: 'Total Devices',
          value: totalDevices.toString(),
          icon: Icons.devices,
          color: Colors.green,
        ),
        _StatCard(
          title: 'Keys Used',
          value: '$usedKeys / $totalKeys',
          icon: Icons.key,
          color: Colors.orange,
        ),
        _StatCard(
          title: 'Total Collection',
          value: '৳${(totalCollection / 100000).toStringAsFixed(1)}L',
          icon: Icons.attach_money,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildTopDealers(Map<String, dynamic> data) {
    final topDealers = (data['top_dealers'] as List<dynamic>?) ?? [];

    if (topDealers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Performers',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            ...List.generate(topDealers.length.clamp(0, 5), (index) {
              final dealer = topDealers[index] as Map<String, dynamic>;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(dealer['name'] as String? ?? 'Unknown'),
                subtitle: Text('${dealer['devices'] ?? 0} devices'),
                trailing: Text(
                  '৳${((dealer['collection'] as num?)?.toDouble() ?? 0) / 1000}k',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}