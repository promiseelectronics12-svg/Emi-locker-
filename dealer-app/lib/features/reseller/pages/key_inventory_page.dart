import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/activation_key.dart';

class KeyInventoryPage extends StatefulWidget {
  const KeyInventoryPage({super.key});

  @override
  State<KeyInventoryPage> createState() => _KeyInventoryPageState();
}

class _KeyInventoryPageState extends State<KeyInventoryPage> {
  final ApiClient _apiClient = ApiClient();

  List<ActivationKey> _keys = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/reseller/keys');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['keys'] as List<dynamic>;
        setState(() {
          _keys = data
              .map((json) => ActivationKey.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load keys';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  int get _totalKeys => _keys.length;
  int get _availableKeys => _keys.where((k) => k.isAvailable).length;
  int get _usedKeys => _keys.where((k) => k.isUsed).length;
  int get _expiredKeys => _keys.where((k) => k.isExpired).length;

  @override
  Widget build(BuildContext context) {
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
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadKeys,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadKeys,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildKeyStatCard(
                                'Total Keys',
                                _totalKeys.toString(),
                                AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildKeyStatCard(
                                'Available',
                                _availableKeys.toString(),
                                AppTheme.successColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildKeyStatCard(
                                'Used',
                                _usedKeys.toString(),
                                AppTheme.warningColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildKeyStatCard(
                                'Expired',
                                _expiredKeys.toString(),
                                AppTheme.errorColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Recent Keys',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._keys.take(20).map((key) => _buildKeyCard(key)),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildKeyStatCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard(ActivationKey key) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (key.isExpired) {
      statusColor = AppTheme.errorColor;
      statusText = 'Expired';
      statusIcon = Icons.error_outline;
    } else if (key.isUsed) {
      statusColor = AppTheme.warningColor;
      statusText = 'Used';
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = AppTheme.successColor;
      statusText = 'Available';
      statusIcon = Icons.vpn_key_outlined;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(
          key.key,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Created: ${key.createdAt.toString().split(' ')[0]}',
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}