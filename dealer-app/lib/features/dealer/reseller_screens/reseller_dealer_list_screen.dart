import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/user_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';
import '../dealer_screens/dealer_device_list_screen.dart';

class ResellerDealerListScreen extends StatefulWidget {
  final bool addMode;

  const ResellerDealerListScreen({
    super.key,
    this.addMode = false,
  });

  @override
  State<ResellerDealerListScreen> createState() => _ResellerDealerListScreenState();
}

class _ResellerDealerListScreenState extends State<ResellerDealerListScreen> {
  List<User> _dealers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _statusFilter = true;

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/dealers',
          queryParameters: {
            'reseller_id': authState.user!.id,
            'status': _statusFilter ? 'active' : 'all',
          },
        );
        final data = response.data as Map<String, dynamic>;
        final dealersJson = data['dealers'] as List<dynamic>;
        _dealers = dealersJson
            .map((json) => User.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load dealers: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<User> get _filteredDealers {
    return _dealers.where((dealer) {
      if (_searchQuery.isEmpty) return true;
      return dealer.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          dealer.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          dealer.phone.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dealers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDealers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDealerDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Dealer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, email, or phone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Active (${_dealers.length})'),
                  selected: _statusFilter,
                  onSelected: (selected) {
                    setState(() => _statusFilter = true);
                    _loadDealers();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('All'),
                  selected: !_statusFilter,
                  onSelected: (selected) {
                    setState(() => _statusFilter = false);
                    _loadDealers();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDealers.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.people_outline,
                        title: 'No dealers found',
                        subtitle: widget.addMode
                            ? 'Add your first dealer to get started'
                            : 'No dealers match your search',
                        action: widget.addMode
                            ? ElevatedButton.icon(
                                onPressed: () => _showAddDealerDialog(),
                                icon: const Icon(Icons.person_add),
                                label: const Text('Add Dealer'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDealers,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
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
    );
  }

  void _showDealerDetails(User dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DealerDetailsSheet(
        dealer: dealer,
        onDeactivate: () => _deactivateDealer(dealer),
      ),
    );
  }

  void _showAddDealerDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddDealerDialog(
        onAdded: () {
          _loadDealers();
        },
      ),
    );
  }

  Future<void> _deactivateDealer(User dealer) async {
    Navigator.pop(context);
    try {
      final apiClient = context.read<ApiClient>();
      await apiClient.put(
        '/dealers/${dealer.id}',
        data: {'status': 'inactive'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dealer deactivated'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDealers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to deactivate dealer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _DealerCard extends StatelessWidget {
  final User dealer;
  final VoidCallback onTap;

  const _DealerCard({
    required this.dealer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryColor,
                child: Text(
                  dealer.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dealer.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dealer.shopName ?? 'N/A',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Validators.formatPhone(dealer.phone),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _DealerDetailsSheet extends StatelessWidget {
  final User dealer;
  final VoidCallback onDeactivate;

  const _DealerDetailsSheet({
    required this.dealer,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(
                      dealer.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          dealer.shopName ?? 'N/A',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Contact Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              InfoRow(label: 'Email', value: dealer.email, copyable: true),
              InfoRow(label: 'Phone', value: dealer.phone, copyable: true),
              InfoRow(label: 'Address', value: dealer.address ?? 'N/A'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Business Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              InfoRow(label: 'Trade License', value: dealer.tradeLicense ?? 'N/A', copyable: true),
              InfoRow(label: 'Reseller Code', value: dealer.resellerCode ?? 'N/A', copyable: true),
              InfoRow(label: 'Member Since', value: Validators.formatDate(dealer.createdAt)),
              InfoRow(label: '2FA Enabled', value: dealer.twoFactorEnabled ? 'Yes' : 'No'),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => _GenerateKeysDialog(dealerId: dealer.id),
                        );
                      },
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('Generate Keys'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DealerDeviceListScreen(dealerId: dealer.id),
                          ),
                        );
                      },
                      icon: const Icon(Icons.devices),
                      label: const Text('View Devices'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onDeactivate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                      ),
                      icon: const Icon(Icons.block),
                      label: const Text('Deactivate'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _AddDealerDialog extends StatefulWidget {
  final VoidCallback onAdded;

  const _AddDealerDialog({required this.onAdded});

  @override
  State<_AddDealerDialog> createState() => _AddDealerDialogState();
}

class _AddDealerDialogState extends State<_AddDealerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _tradeLicenseController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _tradeLicenseController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _addDealer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        await apiClient.post(
          '/dealers',
          data: {
            'reseller_id': authState.user!.id,
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'phone': _phoneController.text.trim(),
            'shop_name': _shopNameController.text.trim(),
            'trade_license': _tradeLicenseController.text.trim().toUpperCase(),
            'address': _addressController.text.trim(),
          },
        );
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dealer added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onAdded();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add dealer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Dealer'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                validator: Validators.validateName,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: Validators.validateEmail,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                validator: Validators.validatePhone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _shopNameController,
                validator: Validators.validateShopName,
                decoration: const InputDecoration(labelText: 'Shop Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tradeLicenseController,
                textCapitalization: TextCapitalization.characters,
                validator: Validators.validateTradeLicense,
                decoration: const InputDecoration(labelText: 'Trade License'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                validator: Validators.validateAddress,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addDealer,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _GenerateKeysDialog extends StatefulWidget {
  final String dealerId;

  const _GenerateKeysDialog({required this.dealerId});

  @override
  State<_GenerateKeysDialog> createState() => _GenerateKeysDialogState();
}

class _GenerateKeysDialogState extends State<_GenerateKeysDialog> {
  final _quantityController = TextEditingController(text: '10');
  bool _isLoading = false;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _generateKeys() async {
    final quantity = int.tryParse(_quantityController.text) ?? 0;
    if (quantity <= 0 || quantity > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter quantity between 1 and 1000'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final apiClient = context.read<ApiClient>();
      final response = await apiClient.post(
        '/activation-keys/generate',
        data: {
          'dealer_id': widget.dealerId,
          'quantity': quantity,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final keys = data['keys'] as List<dynamic>;

      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => _GeneratedKeysDialog(keys: keys.cast<String>()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate keys: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate Activation Keys'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter the number of activation keys to generate:'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _generateKeys,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }
}

class _GeneratedKeysDialog extends StatelessWidget {
  final List<String> keys;

  const _GeneratedKeysDialog({required this.keys});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Keys Generated'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${keys.length} activation keys generated:'),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      keys[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}