import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/user.dart';

class DealersListPage extends StatefulWidget {
  const DealersListPage({super.key});

  @override
  State<DealersListPage> createState() => _DealersListPageState();
}

class _DealersListPageState extends State<DealersListPage> {
  final ApiClient _apiClient = ApiClient();

  List<User> _dealers = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/reseller/dealers');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['dealers'] as List<dynamic>;
        setState(() {
          _dealers = data
              .map((json) => User.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load dealers';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<User> get _filteredDealers {
    if (_searchQuery.isEmpty) return _dealers;

    final query = _searchQuery.toLowerCase();
    return _dealers.where((dealer) {
      return dealer.name.toLowerCase().contains(query) ||
          dealer.shopName.toLowerCase().contains(query) ||
          dealer.email.toLowerCase().contains(query) ||
          dealer.phone.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Dealers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.pushNamed(context, '/add-dealer');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search dealers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadDealers,
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
                                onPressed: _loadDealers,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredDealers.isEmpty
                          ? const Center(
                              child: Text('No dealers found'),
                            )
                          : ListView.builder(
                              itemCount: _filteredDealers.length,
                              itemBuilder: (context, index) {
                                final dealer = _filteredDealers[index];
                                return _buildDealerCard(dealer);
                              },
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add-dealer');
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDealerCard(User dealer) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor,
          child: Text(
            dealer.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          dealer.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dealer.shopName),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone, size: 14, color: AppTheme.textSecondaryColor),
                const SizedBox(width: 4),
                Text(dealer.phone),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.email, size: 14, color: AppTheme.textSecondaryColor),
                const SizedBox(width: 4),
                Text(dealer.email),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                Navigator.pushNamed(context, '/dealer-detail', arguments: dealer);
                break;
              case 'sell_keys':
                Navigator.pushNamed(context, '/sell-keys', arguments: dealer);
                break;
              case 'deactivate':
                _showDeactivateDialog(dealer);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: ListTile(
                leading: Icon(Icons.visibility),
                title: Text('View Details'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'sell_keys',
              child: ListTile(
                leading: Icon(Icons.sell),
                title: Text('Sell Keys'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'deactivate',
              child: ListTile(
                leading: Icon(Icons.block, color: AppTheme.errorColor),
                title: Text('Deactivate'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () {
          Navigator.pushNamed(context, '/dealer-detail', arguments: dealer);
        },
      ),
    );
  }

  void _showDeactivateDialog(User dealer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Dealer'),
        content: Text(
          'Are you sure you want to deactivate ${dealer.name}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }
}