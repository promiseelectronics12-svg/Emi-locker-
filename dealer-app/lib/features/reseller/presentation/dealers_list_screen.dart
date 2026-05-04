import 'package:flutter/material.dart';
import '../../../shared/models/user.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';

class DealersListScreen extends StatefulWidget {
  const DealersListScreen({super.key});

  @override
  State<DealersListScreen> createState() => _DealersListScreenState();
}

class _DealersListScreenState extends State<DealersListScreen> {
  final ApiClient _apiClient = ApiClient();
  List<User> _dealers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/reseller/dealers');
      if (response.statusCode == 200) {
        final List<dynamic> dealersJson = response.data['dealers'] ?? [];
        _dealers = dealersJson
            .map((json) => User.fromJson(json as Map<String, dynamic>))
            .where((u) => u.role == UserRole.dealer)
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load dealers'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<User> get _filteredDealers {
    return _dealers.where((dealer) {
      return _searchQuery.isEmpty ||
          dealer.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          dealer.shopName?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false ||
          dealer.phone.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDealers,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search by name, shop, or phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadDealers,
                    child: _filteredDealers.isEmpty
                        ? _buildEmptyState()
                        : _buildDealersList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/add-dealer'),
        icon: const Icon(Icons.add),
        label: const Text('Add Dealer'),
        backgroundColor: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.store_outlined,
            size: 80,
            color: AppTheme.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'No dealers match your search'
                : 'No dealers registered yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to add a new dealer',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDealersList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredDealers.length,
      itemBuilder: (context, index) {
        final dealer = _filteredDealers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryLight,
              child: Text(
                dealer.name.isNotEmpty ? dealer.name[0].toUpperCase() : 'D',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            title: Text(dealer.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dealer.shopName != null) Text(dealer.shopName!),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      dealer.phone,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.vpn_key, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${dealer.availableKeys} keys',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'view') {
                  Navigator.pushNamed(
                    context,
                    '/dealer-details',
                    arguments: dealer,
                  );
                } else if (value == 'keys') {
                  Navigator.pushNamed(
                    context,
                    '/allocate-keys',
                    arguments: dealer,
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility, size: 20),
                      SizedBox(width: 8),
                      Text('View Details'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'keys',
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
            onTap: () => Navigator.pushNamed(
              context,
              '/dealer-details',
              arguments: dealer,
            ),
          ),
        );
      },
    );
  }
}
