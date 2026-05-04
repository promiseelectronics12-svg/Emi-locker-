import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/models/user_model.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

class DealerManagementScreen extends StatefulWidget {
  const DealerManagementScreen({super.key});

  @override
  State<DealerManagementScreen> createState() => _DealerManagementScreenState();
}

class _DealerManagementScreenState extends State<DealerManagementScreen> {
  final ApiClient _apiClient = ApiClient();
  List<UserModel> _dealers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;

      final response = await _apiClient.get(
        '/reseller/dealers',
        queryParameters: {'reseller_id': authState.user.resellerId},
      );

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = response.data['dealers'];
        setState(() {
          _dealers = data.map((d) => UserModel.fromJson(d)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<UserModel> get _filteredDealers {
    return _dealers.where((dealer) {
      final matchesSearch = _searchQuery.isEmpty ||
          dealer.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          dealer.phone.contains(_searchQuery);
      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Dealers'),
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
              decoration: const InputDecoration(
                hintText: 'Search dealers...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Loading dealers...')
                : _filteredDealers.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.store,
                        title: 'No Dealers',
                        subtitle: 'Dealers will appear here once they register',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDealers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredDealers.length,
                          itemBuilder: (context, index) {
                            final dealer = _filteredDealers[index];
                            return _DealerCard(
                              dealer: dealer,
                              onTap: () => _showDealerDetails(dealer),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDealerDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Dealer'),
      ),
    );
  }

  void _showDealerDetails(UserModel dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DealerDetailsSheet(
        dealer: dealer,
        onActivate: () => _activateDealer(dealer),
        onDeactivate: () => _deactivateDealer(dealer),
        onAddKeys: () => _showAddKeysDialog(dealer),
      ),
    );
  }

  Future<void> _activateDealer(UserModel dealer) async {
    try {
      await _apiClient.post('/reseller/dealers/${dealer.id}/activate');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dealer activated successfully'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
        _loadDealers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to activate dealer'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deactivateDealer(UserModel dealer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Dealer'),
        content: Text('Are you sure you want to deactivate ${dealer.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiClient.post('/reseller/dealers/${dealer.id}/deactivate');
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dealer deactivated'),
              backgroundColor: AppTheme.secondaryColor,
            ),
          );
          _loadDealers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to deactivate dealer'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  void _showAddDealerDialog() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dealers register through the app using your code'),
      ),
    );
  }

  void _showAddKeysDialog(UserModel dealer) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Keys to ${dealer.name}'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Keys',
            hintText: 'Enter quantity',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final count = int.tryParse(amountController.text);
              if (count != null && count > 0) {
                Navigator.pop(context);
                await _addKeysToDealer(dealer, count);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addKeysToDealer(UserModel dealer, int count) async {
    try {
      await _apiClient.post('/reseller/dealers/${dealer.id}/keys', data: {
        'count': count,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added $count keys to ${dealer.name}'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add keys'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
}

class _DealerCard extends StatelessWidget {
  final UserModel dealer;
  final VoidCallback onTap;

  const _DealerCard({required this.dealer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            dealer.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              fontSize: 20,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          dealer.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dealer.phone),
            const SizedBox(height: 4),
            Text(
              'Joined: ${dealer.createdAt.day}/${dealer.createdAt.month}/${dealer.createdAt.year}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _DealerDetailsSheet extends StatelessWidget {
  final UserModel dealer;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onAddKeys;

  const _DealerDetailsSheet({
    required this.dealer,
    required this.onActivate,
    required this.onDeactivate,
    required this.onAddKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  dealer.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dealer.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(dealer.phone),
                    Text(dealer.email),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          _DetailRow(label: 'Status', value: 'Active'),
          _DetailRow(
            label: 'Member Since',
            value:
                '${dealer.createdAt.day}/${dealer.createdAt.month}/${dealer.createdAt.year}',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddKeys,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Keys'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.block),
                  label: const Text('Deactivate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}