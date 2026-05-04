import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/services/api_client.dart';
import '../../shared/models/user.dart';
import '../auth/auth_bloc.dart';

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
      final authState = context.read<AuthBloc>().state;
      final response = await _apiClient.get(
        '/dealers',
        queryParameters: {'reseller_id': authState.user?.id},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['dealers'] ?? [];
        _dealers = data.map((json) => User.fromJson(json)).toList();
      }
    } catch (e) {
      // Handle silently
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<User> get _filteredDealers {
    if (_searchQuery.isEmpty) return _dealers;
    return _dealers.where((dealer) {
      final query = _searchQuery.toLowerCase();
      return dealer.name.toLowerCase().contains(query) ||
          dealer.shopName?.toLowerCase().contains(query) == true ||
          dealer.email.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dealers'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search dealers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const LoadingIndicator(message: 'Loading dealers...')
                : _filteredDealers.isEmpty
                    ? const EmptyState(
                        icon: Icons.store_outlined,
                        title: 'No Dealers',
                        subtitle: 'Add your first dealer to get started',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDealers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredDealers.length,
                          itemBuilder: (context, index) {
                            final dealer = _filteredDealers[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppTheme.primaryColor.withOpacity(0.1),
                                  child: Text(
                                    dealer.name.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(dealer.shopName ?? dealer.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dealer.name),
                                    Text(
                                      dealer.phone,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'view') {
                                      Navigator.pushNamed(
                                        context,
                                        '/dealer-details',
                                        arguments: dealer.id,
                                      );
                                    } else if (value == 'keys') {
                                      Navigator.pushNamed(
                                        context,
                                        '/dealer-keys',
                                        arguments: dealer.id,
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'view',
                                      child: ListTile(
                                        leading: Icon(Icons.visibility),
                                        title: Text('View'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'keys',
                                      child: ListTile(
                                        leading: Icon(Icons.vpn_key),
                                        title: Text('Assign Keys'),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/add-dealer'),
        icon: const Icon(Icons.add),
        label: const Text('Add Dealer'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}