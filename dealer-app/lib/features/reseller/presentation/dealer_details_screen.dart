import 'package:flutter/material.dart';
import '../../../shared/models/user.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';

class DealerDetailsScreen extends StatefulWidget {
  final User dealer;

  const DealerDetailsScreen({super.key, required this.dealer});

  @override
  State<DealerDetailsScreen> createState() => _DealerDetailsScreenState();
}

class _DealerDetailsScreenState extends State<DealerDetailsScreen> {
  final ApiClient _apiClient = ApiClient();
  late User _dealer;
  bool _isLoading = true;
  Map<String, dynamic> _dealerStats = {};

  @override
  void initState() {
    super.initState();
    _dealer = widget.dealer;
    _loadDealerDetails();
  }

  Future<void> _loadDealerDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/reseller/dealers/${_dealer.id}');
      if (response.statusCode == 200) {
        _dealerStats = Map<String, dynamic>.from(response.data);
        if (_dealerStats['user'] != null) {
          _dealer = User.fromJson(_dealerStats['user'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dealer details'),
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
        title: const Text('Dealer Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDealerDetails,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'allocate') {
                Navigator.pushNamed(
                  context,
                  '/allocate-keys',
                  arguments: _dealer,
                ).then((result) {
                  if (result == true) {
                    _loadDealerDetails();
                  }
                });
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'allocate',
                child: Row(
                  children: [
                    Icon(Icons.vpn_key, size: 20),
                    SizedBox(width: 8),
                    Text('Allocate Keys'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDealerDetails,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileCard(),
                    const SizedBox(height: 16),
                    _buildKeysCard(),
                    const SizedBox(height: 16),
                    _buildStatsCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.primaryLight,
              child: Text(
                _dealer.name.isNotEmpty ? _dealer.name[0].toUpperCase() : 'D',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _dealer.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_dealer.shopName != null) ...[
              const SizedBox(height: 4),
              Text(
                _dealer.shopName!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildContactItem(Icons.phone, _dealer.phone),
                const SizedBox(width: 24),
                _buildContactItem(Icons.email, _dealer.email),
              ],
            ),
            if (_dealer.tradeLicense != null) ...[
              const SizedBox(height: 8),
              _buildContactItem(Icons.description, _dealer.tradeLicense!),
            ],
            if (_dealer.address != null) ...[
              const SizedBox(height: 8),
              _buildContactItem(Icons.location_on, _dealer.address!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildKeysCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Inventory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildKeyStat(
                    'Available',
                    _dealer.availableKeys.toString(),
                    AppTheme.successColor,
                  ),
                ),
                Expanded(
                  child: _buildKeyStat(
                    'Used',
                    _dealer.usedKeys.toString(),
                    AppTheme.primaryColor,
                  ),
                ),
                Expanded(
                  child: _buildKeyStat(
                    'Total',
                    (_dealer.availableKeys + _dealer.usedKeys).toString(),
                    AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/allocate-keys',
                    arguments: _dealer,
                  ).then((result) {
                    if (result == true) {
                      _loadDealerDetails();
                    }
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('Allocate More Keys'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildStatsCard() {
    final totalDevices = _dealerStats['total_devices'] ?? 0;
    final activeDevices = _dealerStats['active_devices'] ?? 0;
    final lockedDevices = _dealerStats['locked_devices'] ?? 0;
    final totalCollection = _dealerStats['total_collection'] ?? 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Stats',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    Icons.phone_android,
                    'Devices',
                    totalDevices.toString(),
                    AppTheme.primaryColor,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    Icons.check_circle,
                    'Active',
                    activeDevices.toString(),
                    AppTheme.successColor,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    Icons.lock,
                    'Locked',
                    lockedDevices.toString(),
                    AppTheme.errorColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Collection'),
                Text(
                  '৳${(totalCollection as double).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
