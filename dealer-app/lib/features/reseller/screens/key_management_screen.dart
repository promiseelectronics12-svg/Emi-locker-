import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/models/activation_key_model.dart';
import '../../shared/services/api_client.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';

class KeyManagementScreen extends StatefulWidget {
  const KeyManagementScreen({super.key});

  @override
  State<KeyManagementScreen> createState() => _KeyManagementScreenState();
}

class _KeyManagementScreenState extends State<KeyManagementScreen> {
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
        '/reseller/keys',
        queryParameters: {'reseller_id': authState.user.resellerId},
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

  Future<void> _generateKeys(int count) async {
    try {
      final response = await _apiClient.post(
        '/reseller/keys/generate',
        data: {'count': count},
      );

      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${response.data['count']} keys'),
            backgroundColor: AppTheme.secondaryColor,
          ),
        );
        _loadKeys();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate keys'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableKeys = _keys.where((k) => !k.isUsed).toList();
    final usedKeys = _keys.where((k) => k.isUsed).toList();

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
      body: _isLoading
          ? const LoadingWidget(message: 'Loading keys...')
          : RefreshIndicator(
              onRefresh: _loadKeys,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCard(availableKeys.length, usedKeys.length),
                    const SizedBox(height: 24),
                    if (availableKeys.isNotEmpty) ...[
                      Text(
                        'Available Keys (${availableKeys.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...availableKeys.map((key) => _KeyListTile(
                            key: key,
                            onTap: () => _showKeyActions(key),
                          )),
                      const SizedBox(height: 24),
                    ],
                    if (usedKeys.isNotEmpty) ...[
                      Text(
                        'Used Keys (${usedKeys.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...usedKeys.map((key) => _KeyListTile(
                            key: key,
                            onTap: () => _showKeyDetails(key),
                          )),
                    ],
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGenerateKeysDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Generate Keys'),
      ),
    );
  }

  Widget _buildSummaryCard(int available, int used) {
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
                  (available + used).toString(),
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
                  available.toString(),
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
                  used.toString(),
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

  void _showGenerateKeysDialog() {
    final controller = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Keys'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Keys',
            hintText: 'Enter quantity to generate',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final count = int.tryParse(controller.text);
              if (count != null && count > 0) {
                Navigator.pop(context);
                _generateKeys(count);
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _showKeyActions(ActivationKeyModel key) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Key: ${key.keyCode}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Key'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: key.keyCode));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Key copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Key'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                _showKeyDetails(key);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyDetails(ActivationKeyModel key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Key Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Key Code', value: key.keyCode),
            _DetailRow(label: 'Status', value: key.isUsed ? 'Used' : 'Available'),
            _DetailRow(
              label: 'Created',
              value:
                  '${key.createdAt.day}/${key.createdAt.month}/${key.createdAt.year}',
            ),
            if (key.isUsed && key.usedAt != null)
              _DetailRow(
                label: 'Used On',
                value:
                    '${key.usedAt!.day}/${key.usedAt!.month}/${key.usedAt!.year}',
              ),
            if (key.dealerId != null)
              _DetailRow(label: 'Dealer ID', value: key.dealerId!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _KeyListTile extends StatelessWidget {
  final ActivationKeyModel key;
  final VoidCallback onTap;

  const _KeyListTile({required this.key, required this.onTap});

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