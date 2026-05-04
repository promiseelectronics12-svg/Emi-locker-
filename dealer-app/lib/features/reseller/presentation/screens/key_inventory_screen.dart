import 'package:flutter/material.dart';
import '../../../../shared/api/api_client.dart';
import '../../../../shared/theme/app_theme.dart';

class ResellerKeyInventoryScreen extends StatefulWidget {
  const ResellerKeyInventoryScreen({super.key});

  @override
  State<ResellerKeyInventoryScreen> createState() => _ResellerKeyInventoryScreenState();
}

class _ResellerKeyInventoryScreenState extends State<ResellerKeyInventoryScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  late TabController _tabController;
  bool _isLoading = true;

  int _totalKeys = 0;
  int _availableKeys = 0;
  int _assignedKeys = 0;
  int _activatedKeys = 0;

  List<Map<String, dynamic>> _keyHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/reseller/key-inventory');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _totalKeys = data['total_keys'] ?? 0;
          _availableKeys = data['available_keys'] ?? 0;
          _assignedKeys = data['assigned_keys'] ?? 0;
          _activatedKeys = data['activated_keys'] ?? 0;
          _keyHistory = List<Map<String, dynamic>>.from(data['history'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load inventory: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Inventory'),
        backgroundColor: AppTheme.resellerColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildTotalKeysCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('Available', '$_availableKeys', AppTheme.successColor)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Assigned', '$_assignedKeys', AppTheme.primaryColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard('Activated', '$_activatedKeys', AppTheme.accentColor)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard('Total', '$_totalKeys', AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 24),
          _buildKeyStatusExplanation(),
        ],
      ),
    );
  }

  Widget _buildTotalKeysCard() {
    return Card(
      color: AppTheme.resellerColor,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(Icons.vpn_key, size: 48, color: Colors.white),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Keys',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$_totalKeys',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_availableKeys available',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.vpn_key, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyStatusExplanation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Status Guide',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildExplanationRow(
              AppTheme.successColor,
              'Available',
              'Keys in your inventory ready to be assigned to dealers',
            ),
            const SizedBox(height: 12),
            _buildExplanationRow(
              AppTheme.primaryColor,
              'Assigned',
              'Keys assigned to dealers but not yet used for device activation',
            ),
            const SizedBox(height: 12),
            _buildExplanationRow(
              AppTheme.accentColor,
              'Activated',
              'Keys that have been used to activate a device',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationRow(Color color, String label, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_keyHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 80,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No key history yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _keyHistory.length,
        itemBuilder: (context, index) {
          final entry = _keyHistory[index];
          return _buildHistoryCard(entry);
        },
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> entry) {
    final type = entry['type'] as String? ?? 'unknown';
    final quantity = entry['quantity'] ?? 0;
    final timestamp = DateTime.tryParse(entry['timestamp'] ?? '');
    final relatedDealer = entry['dealer_name'] as String?;

    IconData icon;
    Color color;
    String title;

    switch (type) {
      case 'purchase':
        icon = Icons.shopping_cart;
        color = AppTheme.primaryColor;
        title = 'Purchased $quantity keys';
        break;
      case 'assignment':
        icon = Icons.send;
        color = AppTheme.accentColor;
        title = 'Assigned $quantity keys';
        break;
      case 'activation':
        icon = Icons.check_circle;
        color = AppTheme.successColor;
        title = '$quantity keys activated';
        break;
      default:
        icon = Icons.vpn_key;
        color = AppTheme.textSecondary;
        title = '$quantity keys - $type';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (relatedDealer != null) Text('Dealer: $relatedDealer'),
            if (timestamp != null)
              Text(
                _formatDateTime(timestamp),
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
          ],
        ),
        isThreeLine: relatedDealer != null,
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}