import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/user.dart';
import '../bloc/auth_bloc.dart';

class ResellerDashboardPage extends StatefulWidget {
  const ResellerDashboardPage({super.key});

  @override
  State<ResellerDashboardPage> createState() => _ResellerDashboardPageState();
}

class _ResellerDashboardPageState extends State<ResellerDashboardPage> {
  final ApiClient _apiClient = ApiClient();

  int _totalDealers = 0;
  int _activeDealers = 0;
  int _totalKeys = 0;
  int _availableKeys = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/reseller/dashboard');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _totalDealers = data['total_dealers'] as int? ?? 0;
          _activeDealers = data['active_dealers'] as int? ?? 0;
          _totalKeys = data['total_keys'] as int? ?? 0;
          _availableKeys = data['available_keys'] as int? ?? 0;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load dashboard data';
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
        title: const Text('Reseller Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDashboardData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Total Dealers',
                                _totalDealers.toString(),
                                AppTheme.primaryColor,
                                Icons.store_outlined,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                'Active Dealers',
                                _activeDealers.toString(),
                                AppTheme.successColor,
                                Icons.check_circle_outline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Total Keys',
                                _totalKeys.toString(),
                                AppTheme.primaryColor,
                                Icons.vpn_key_outlined,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                'Available Keys',
                                _availableKeys.toString(),
                                AppTheme.successColor,
                                Icons.key_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildActionCard(
                          'Manage Dealers',
                          'View and manage your dealer network',
                          Icons.people_outline,
                          () => Navigator.pushNamed(context, '/dealers'),
                        ),
                        _buildActionCard(
                          'Key Inventory',
                          'Manage activation keys inventory',
                          Icons.vpn_key_outlined,
                          () => Navigator.pushNamed(context, '/key-inventory'),
                        ),
                        _buildActionCard(
                          'Sell Keys',
                          'Sell activation keys to dealers',
                          Icons.sell_outlined,
                          () => Navigator.pushNamed(context, '/sell-keys'),
                        ),
                        _buildActionCard(
                          'Analytics',
                          'View sales and dealer performance',
                          Icons.analytics_outlined,
                          () => Navigator.pushNamed(context, '/reseller-analytics'),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildStatCard(
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
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}