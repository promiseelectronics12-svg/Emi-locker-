import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/models/activation_key_model.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../bloc/auth_bloc.dart';

class KeyInventoryScreen extends StatefulWidget {
  const KeyInventoryScreen({super.key});

  @override
  State<KeyInventoryScreen> createState() => _KeyInventoryScreenState();
}

class _KeyInventoryScreenState extends State<KeyInventoryScreen> {
  final ApiClient _apiClient = ApiClient();
  List<ActivationKeyModel> _keys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;

      final response = await _apiClient.get(
        '/keys',
        queryParameters: {'dealer_id': authState.user.dealerId},
      );

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = response.data['keys'];
        setState(() {
          _keys = data.map((k) => ActivationKeyModel.fromJson(k)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedKeys = _keys.where((k) => k.isUsed).toList();
    final unusedKeys = _keys.where((k) => !k.isUsed).toList();

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
      body: _isLoading
          ? const LoadingWidget(message: 'Loading keys...')
          : _keys.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.key_off,
                  title: 'No Keys',
                  subtitle: 'Purchase activation keys from your reseller',
                )
              : RefreshIndicator(
                  onRefresh: _loadKeys,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryCard(usedKeys.length, unusedKeys.length),
                        const SizedBox(height: 24),
                        if (unusedKeys.isNotEmpty) ...[
                          Text(
                            'Available Keys (${unusedKeys.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          ...unusedKeys.map((key) => _KeyCard(
                                key: key,
                                onTap: () => _showKeyDetails(key),
                              )),
                          const SizedBox(height: 24),
                        ],
                        if (usedKeys.isNotEmpty) ...[
                          Text(
                            'Used Keys (${usedKeys.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          ...usedKeys.map((key) => _KeyCard(
                                key: key,
                                onTap: () => _showKeyDetails(key),
                              )),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSummaryCard(int usedCount, int unusedCount) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text(
                  (usedCount + unusedCount).toString(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Text('Total Keys'),
              ],
            ),
            Column(
              children: [
                Text(
                  unusedCount.toString(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                ),
                const Text('Available'),
              ],
            ),
            Column(
              children: [
                Text(
                  usedCount.toString(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                ),
                const Text('Used'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyDetails(ActivationKeyModel key) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            _DetailRow(label: 'Key Code', value: key.keyCode),
            _DetailRow(label: 'Status', value: key.isUsed ? 'Used' : 'Available'),
            _DetailRow(
              label: 'Created',
              value: '${key.createdAt.day}/${key.createdAt.month}/${key.createdAt.year}',
            ),
            if (key.isUsed && key.usedAt != null)
              _DetailRow(
                label: 'Used On',
                value: '${key.usedAt!.day}/${key.usedAt!.month}/${key.usedAt!.year}',
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  final ActivationKeyModel key;
  final VoidCallback onTap;

  const _KeyCard({required this.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.key,
          color: key.isUsed ? Colors.grey : Colors.green,
        ),
        title: Text(
          key.keyCode,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          key.isUsed
              ? 'Used on ${key.usedAt?.day}/${key.usedAt?.month}/${key.usedAt?.year}'
              : 'Available',
        ),
        trailing: Icon(
          key.isUsed ? Icons.check_circle : Icons.radio_button_unchecked,
          color: key.isUsed ? Colors.grey : Colors.green,
        ),
        onTap: onTap,
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