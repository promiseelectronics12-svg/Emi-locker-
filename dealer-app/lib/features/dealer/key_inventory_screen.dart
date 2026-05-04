import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/services/api_client.dart';
import '../../shared/models/activation_key.dart';
import '../auth/auth_bloc.dart';

class KeyInventoryScreen extends StatefulWidget {
  const KeyInventoryScreen({super.key});

  @override
  State<KeyInventoryScreen> createState() => _KeyInventoryScreenState();
}

class _KeyInventoryScreenState extends State<KeyInventoryScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  late TabController _tabController;

  List<ActivationKey> _availableKeys = [];
  List<ActivationKey> _usedKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadKeys();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadKeys() async {
    setState(() => _isLoading = true);

    try {
      final authState = context.read<AuthBloc>().state;
      final response = await _apiClient.get(
        '/activation-keys',
        queryParameters: {'dealer_id': authState.user?.id},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['keys'] ?? [];
        final keys = data.map((json) => ActivationKey.fromJson(json)).toList();
        setState(() {
          _availableKeys = keys.where((k) => !k.isUsed).toList();
          _usedKeys = keys.where((k) => k.isUsed).toList();
        });
      }
    } catch (e) {
      // Handle silently
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Inventory'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Available (${_availableKeys.length})'),
            Tab(text: 'Used (${_usedKeys.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingIndicator(message: 'Loading keys...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildKeyList(_availableKeys, isUsed: false),
                _buildKeyList(_usedKeys, isUsed: true),
              ],
            ),
    );
  }

  Widget _buildKeyList(List<ActivationKey> keys, {required bool isUsed}) {
    if (keys.isEmpty) {
      return EmptyState(
        icon: isUsed ? Icons.check_circle_outline : Icons.vpn_key_outlined,
        title: isUsed ? 'No Used Keys' : 'No Available Keys',
        subtitle: isUsed
            ? 'Keys that have been used will appear here'
            : 'Purchase keys from your reseller to get started',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadKeys,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isUsed
                      ? AppTheme.successColor.withOpacity(0.1)
                      : AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.vpn_key,
                  color: isUsed ? AppTheme.successColor : AppTheme.primaryColor,
                ),
              ),
              title: Text(
                key.keyCode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Created: ${key.createdAt.toString().split(' ')[0]}',
                  ),
                  if (isUsed && key.usedAt != null)
                    Text(
                      'Used: ${key.usedAt.toString().split(' ')[0]}',
                      style: const TextStyle(color: AppTheme.successColor),
                    ),
                ],
              ),
              trailing: isUsed
                  ? const Icon(Icons.check_circle, color: AppTheme.successColor)
                  : null,
            ),
          );
        },
      ),
    );
  }
}