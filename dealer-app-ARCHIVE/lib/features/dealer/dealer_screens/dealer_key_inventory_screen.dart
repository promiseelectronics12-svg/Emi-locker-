import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/activation_key_model.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/utils/validators.dart';
import '../auth/bloc/auth_bloc.dart';
import '../auth/auth_state.dart';

class DealerKeyInventoryScreen extends StatefulWidget {
  const DealerKeyInventoryScreen({super.key});

  @override
  State<DealerKeyInventoryScreen> createState() => _DealerKeyInventoryScreenState();
}

class _DealerKeyInventoryScreenState extends State<DealerKeyInventoryScreen> {
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
          queryParameters: {'dealer_id': authState.user!.id},
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
    if (_filter == 'USED') return _keys.where((k) => k.isUsed).toList();
    return _keys.where((k) => !k.isUsed).toList();
  }

  @override
  Widget build(BuildContext context) {
    final availableCount = _keys.where((k) => !k.isUsed).length;
    final usedCount = _keys.where((k) => k.isUsed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadKeys,
          ),
        ],
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
                  label: 'Used',
                  value: '$usedCount',
                  color: Colors.grey,
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
                  label: 'Used ($usedCount)',
                  isSelected: _filter == 'USED',
                  onTap: () => setState(() => _filter = 'USED'),
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
                        subtitle: 'Purchase keys from your reseller',
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
            InfoRow(label: 'Status', value: keyData.isUsed ? 'Used' : 'Available'),
            InfoRow(label: 'Created', value: Validators.formatDateTime(keyData.createdAt)),
            if (keyData.isUsed && keyData.usedAt != null)
              InfoRow(label: 'Used On', value: Validators.formatDateTime(keyData.usedAt!)),
            if (keyData.isUsed && keyData.deviceId != null)
              InfoRow(label: 'Device ID', value: keyData.deviceId!, copyable: true),
            const SizedBox(height: 24),
          ],
        ),
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
                      ? Colors.grey.withValues(alpha: 0.1)
                      : AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.vpn_key,
                  color: keyData.isUsed ? Colors.grey : AppTheme.successColor,
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
              StatusBadge(status: keyData.isUsed ? 'used' : 'available'),
            ],
          ),
        ),
      ),
    );
  }
}