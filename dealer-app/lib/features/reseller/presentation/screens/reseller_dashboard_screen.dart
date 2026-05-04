import 'package:flutter/material.dart';
import '../../../../shared/api/api_client.dart';
import '../../../../shared/repositories/reseller_repository.dart';
import '../../../../shared/models/reseller_stats.dart';
import '../../../../shared/models/dealer_application.dart';
import '../../../../shared/models/dealer.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/common_widgets.dart';
import 'dealer_management_screen.dart';
import 'key_request_screen.dart';

class ResellerDashboardScreen extends StatefulWidget {
  const ResellerDashboardScreen({super.key});

  @override
  State<ResellerDashboardScreen> createState() =>
      _ResellerDashboardScreenState();
}

class _ResellerDashboardScreenState extends State<ResellerDashboardScreen> {
  late final ResellerRepository _repository;
  ResellerStats? _stats;
  List<DealerApplication> _pendingApplications = [];
  List<Dealer> _dealers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = ResellerRepository(ApiClient());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _repository.getResellerStats(),
        _repository.getDealerApplications(status: 'pending'),
        _repository.getDealers(),
      ]);

      setState(() {
        _stats = results[0] as ResellerStats;
        _pendingApplications = results[1] as List<DealerApplication>;
        _dealers = results[2] as List<Dealer>;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reseller Dashboard'),
        backgroundColor: AppTheme.resellerColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuotaProgress(),
                        const SizedBox(height: 24),
                        _buildKeyInventory(),
                        const SizedBox(height: 24),
                        _buildDealerList(),
                        const SizedBox(height: 24),
                        _buildPendingApplications(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _error ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaProgress() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    final percentage = stats.quotaUsedPercentage.clamp(0, 100);
    final progressColor = percentage >= 90
        ? Colors.red
        : percentage >= 70
            ? Colors.orange
            : AppTheme.successColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Monthly Quota',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${stats.keysUsedThisMonth} / ${stats.monthlyQuota}',
                  style: TextStyle(
                    fontSize: 14,
                    color: progressColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${percentage.toStringAsFixed(1)}% used',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyInventory() {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Key Inventory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () => _navigateToKeyRequest(),
              child: const Text('Request Keys'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _KeyInventoryCard(
                title: 'Purchased',
                value: stats.keysPurchased,
                icon: Icons.shopping_cart,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeyInventoryCard(
                title: 'Assigned',
                value: stats.keysAssigned,
                icon: Icons.assignment,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeyInventoryCard(
                title: 'Available',
                value: stats.keysAvailable,
                icon: Icons.check_circle,
                color: AppTheme.successColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDealerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Dealers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: () => _navigateToDealerManagement(),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_dealers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No dealers yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          ...List.generate(
            _dealers.length > 3 ? 3 : _dealers.length,
            (index) {
              final dealer = _dealers[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.resellerColor.withOpacity(0.1),
                    child: Text(
                      dealer.name.isNotEmpty ? dealer.name[0].toUpperCase() : 'D',
                      style: const TextStyle(
                        color: AppTheme.resellerColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(dealer.shopName.isNotEmpty ? dealer.shopName : dealer.name),
                  subtitle: Text(
                    '${dealer.activeDevices} active / ${dealer.totalDevices} total devices',
                  ),
                  trailing: _buildDealerStatusChip('active'),
                  onTap: () => _navigateToDealerManagement(),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPendingApplications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pending Applications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_pendingApplications.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_pendingApplications.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_pendingApplications.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    const Text(
                      'No pending applications',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...List.generate(
            _pendingApplications.length > 2 ? 2 : _pendingApplications.length,
            (index) {
              final application = _pendingApplications[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withOpacity(0.1),
                    child: const Icon(Icons.pending, color: Colors.orange),
                  ),
                  title: Text(application.name),
                  subtitle: Text(application.shopName),
                  trailing: TextButton(
                    onPressed: () => _navigateToDealerManagement(),
                    child: const Text('Review'),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDealerStatusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'active':
        color = AppTheme.successColor;
        break;
      case 'suspended':
        color = Colors.red;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _navigateToDealerManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DealerManagementScreen(),
      ),
    );
  }

  void _navigateToKeyRequest() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const KeyRequestScreen(),
      ),
    );
  }
}

class _KeyInventoryCard extends StatelessWidget {
  final String title;
  final int value;
  final IconData icon;
  final Color color;

  const _KeyInventoryCard({
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
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}