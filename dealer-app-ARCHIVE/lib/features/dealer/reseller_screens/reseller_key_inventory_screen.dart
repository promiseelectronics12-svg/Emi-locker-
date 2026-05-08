import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/activation_key_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class ResellerKeyInventoryScreen extends StatefulWidget {
  final bool generationMode;

  const ResellerKeyInventoryScreen({
    super.key,
    this.generationMode = false,
  });

  @override
  State<ResellerKeyInventoryScreen> createState() => _ResellerKeyInventoryScreenState();
}

class _ResellerKeyInventoryScreenState extends State<ResellerKeyInventoryScreen> {
  List<ActivationKey> _keys = [];
  bool _isLoading = true;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/activation-keys',
          queryParameters: {'reseller_id': authState.user!.id},
        );
        final data = response.data as Map<String, dynamic>;
        final keysJson = data['keys'] as List<dynamic>;
        setState(() {
          _keys = keysJson
              .map((json) => ActivationKey.fromJson(json as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load keys: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<ActivationKey> get _filteredKeys {
    if (_filter == 'ALL') return _keys;
    if (_filter == 'SOLD') return _keys.where((k) => k.isUsed).toList();
    return _keys.where((k) => !k.isUsed).toList();
  }

  @override
  Widget build(BuildContext context) {
    final availableCount = _keys.where((k) => !k.isUsed).length;
    final soldCount = _keys.where((k) => k.isUsed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadKeys,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGenerateKeysDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Generate Keys'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _KeyStatCard(
                  label: 'Total Keys',
                  value: '${_keys.length}',
                  color: AppTheme.primaryColor,
                ),
                _KeyStatCard(
                  label: 'Available',
                  value: '$availableCount',
                  color: AppTheme.successColor,
                ),
                _KeyStatCard(
                  label: 'Sold/Used',
                  value: '$soldCount',
                  color: Colors.purple,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All (${_keys.length})',
                  isSelected: _filter == 'ALL',
                  onTap: () => setState(() => _filter = 'ALL'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Available ($availableCount)',
                  isSelected: _filter == 'AVAILABLE',
                  onTap: () => setState(() => _filter = 'AVAILABLE'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Sold ($soldCount)',
                  isSelected: _filter == 'SOLD',
                  onTap: () => setState(() => _filter = 'SOLD'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredKeys.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.vpn_key,
                        title: 'No keys found',
                        subtitle: 'Generate activation keys to sell to dealers',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadKeys,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredKeys.length,
                          itemBuilder: (context, index) {
                            final key = _filteredKeys[index];
                            return _KeyCard(
                              keyData: key,
                              onTap: () => _showKeyDetails(key),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showKeyDetails(ActivationKey keyData) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const Text(
              'Activation Key Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            InfoRow(label: 'Key Code', value: keyData.keyCode, copyable: true),
            InfoRow(label: 'Status', value: keyData.isUsed ? 'Sold/Used' : 'Available'),
            InfoRow(label: 'Created', value: Validators.formatDateTime(keyData.createdAt)),
            if (keyData.isUsed && keyData.usedAt != null)
              InfoRow(label: 'Used On', value: Validators.formatDateTime(keyData.usedAt!)),
            if (keyData.isUsed && keyData.dealerId != null)
              InfoRow(label: 'Dealer ID', value: keyData.dealerId!, copyable: true),
            if (keyData.isUsed && keyData.deviceId != null)
              InfoRow(label: 'Device ID', value: keyData.deviceId!, copyable: true),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showGenerateKeysDialog() {
    showDialog(
      context: context,
      builder: (context) => _GenerateKeysDialog(
        onGenerated: () {
          _loadKeys();
        },
      ),
    );
  }
}

class _KeyStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _KeyStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  final ActivationKey keyData;
  final VoidCallback onTap;

  const _KeyCard({
    required this.keyData,
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: keyData.isUsed
                      ? Colors.purple.withValues(alpha: 0.1)
                      : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.vpn_key,
                  color: keyData.isUsed ? Colors.purple : AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      keyData.keyCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Created: ${Validators.formatDateTime(keyData.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(status: keyData.isUsed ? 'sold' : 'available'),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerateKeysDialog extends StatefulWidget {
  final VoidCallback onGenerated;

  const _GenerateKeysDialog({required this.onGenerated});

  @override
  State<_GenerateKeysDialog> createState() => _GenerateKeysDialogState();
}

class _GenerateKeysDialogState extends State<_GenerateKeysDialog> {
  final _quantityController = TextEditingController(text: '10');
  final _dealerIdController = TextEditingController();
  List<Map<String, dynamic>> _dealers = [];
  String? _selectedDealerId;
  bool _isLoading = false;
  bool _isLoadingDealers = false;

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _dealerIdController.dispose();
    super.dispose();
  }

  Future<void> _loadDealers() async {
    setState(() => _isLoadingDealers = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final apiClient = context.read<ApiClient>();
        final response = await apiClient.get(
          '/dealers',
          queryParameters: {'reseller_id': authState.user!.id},
        );
        final data = response.data as Map<String, dynamic>;
        final dealersJson = data['dealers'] as List<dynamic>;
        setState(() {
          _dealers = dealersJson.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      // Handle error silently
    } finally {
      setState(() => _isLoadingDealers = false);
    }
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

    if (_selectedDealerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a dealer'),
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
          'dealer_id': _selectedDealerId,
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
        widget.onGenerated();
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Dealer:'),
            const SizedBox(height: 8),
            _isLoadingDealers
                ? const CircularProgressIndicator()
                : DropdownButtonFormField<String>(
                    value: _selectedDealerId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select a dealer',
                    ),
                    items: _dealers.map((dealer) {
                      return DropdownMenuItem(
                        value: dealer['id'] as String,
                        child: Text(dealer['name'] as String),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedDealerId = value);
                    },
                  ),
            const SizedBox(height: 16),
            const Text('Number of keys:'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter quantity',
              ),
            ),
          ],
        ),
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
      title: const Text('Keys Generated Successfully'),
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