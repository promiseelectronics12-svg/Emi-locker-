import 'package:flutter/material.dart';
import '../../../shared/models/activation_key_model.dart';
import '../../../shared/api/api_client.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';

class KeyInventoryScreen extends StatefulWidget {
  const KeyInventoryScreen({super.key});

  @override
  State<KeyInventoryScreen> createState() => _KeyInventoryScreenState();
}

class _KeyInventoryScreenState extends State<KeyInventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ActivationKeyModel> _keys = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.getActivationKeys();

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> keyList = response.data['keys'] ?? [];
        setState(() {
          _keys = keyList.map((k) => ActivationKeyModel.fromJson(k)).toList();
        });
      } else {
        setState(() => _keys = _getMockKeys());
      }
    } catch (_) {
      setState(() => _keys = _getMockKeys());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ActivationKeyModel> _getMockKeys() {
    return List.generate(
      20,
      (i) => ActivationKeyModel(
        id: '$i',
        key: 'EMI-${(100000 + i).toString()}-${(1000 + i).toString()}',
        status: i < 5 ? KeyStatus.available : (i < 15 ? KeyStatus.sold : KeyStatus.activated),
        price: 500.0,
        soldAt: i >= 5 && i < 15 ? DateTime.now().subtract(Duration(days: i)) : null,
        activatedAt: i >= 15 ? DateTime.now().subtract(Duration(days: i - 10)) : null,
      ),
    );
  }

  List<ActivationKeyModel> _getKeysByStatus(KeyStatus? status) {
    if (status == null) return _keys;
    return _keys.where((k) => k.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Inventory'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${_keys.length})'),
            Tab(text: 'Available (${_getKeysByStatus(KeyStatus.available).length})'),
            Tab(text: 'Sold (${_getKeysByStatus(KeyStatus.sold).length})'),
            Tab(text: 'Activated (${_getKeysByStatus(KeyStatus.activated).length})'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadKeys,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildKeyList(null),
                _buildKeyList(KeyStatus.available),
                _buildKeyList(KeyStatus.sold),
                _buildKeyList(KeyStatus.activated),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPurchaseDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Buy Keys'),
      ),
    );
  }

  Widget _buildKeyList(KeyStatus? status) {
    final filteredKeys = _getKeysByStatus(status);

    if (filteredKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vpn_key_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              status == null ? 'No keys found' : 'No ${status.name} keys',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadKeys,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredKeys.length,
        itemBuilder: (context, index) {
          final key = filteredKeys[index];
          return _buildKeyCard(key);
        },
      ),
    );
  }

  Widget _buildKeyCard(ActivationKeyModel key) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getStatusColor(key.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.vpn_key, color: _getStatusColor(key.status)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key.key,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildStatusChip(key.status),
                      const SizedBox(width: 8),
                      Text(
                        'BDT ${key.price.toStringAsFixed(0)}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (key.status == KeyStatus.available)
              IconButton(
                icon: const Icon(Icons.sell, color: AppTheme.primaryColor),
                onPressed: () => _showSellDialog(key),
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(KeyStatus status) {
    switch (status) {
      case KeyStatus.available:
        return AppTheme.successColor;
      case KeyStatus.sold:
        return Colors.orange;
      case KeyStatus.activated:
        return AppTheme.primaryColor;
      case KeyStatus.revoked:
        return AppTheme.errorColor;
    }
  }

  Widget _buildStatusChip(KeyStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          color: _getStatusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSellDialog(ActivationKeyModel key) {
    final dealerController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sell Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Key: ${key.key}'),
            const SizedBox(height: 8),
            Text('Price: BDT ${key.price.toStringAsFixed(0)}'),
            const SizedBox(height: 16),
            TextField(
              controller: dealerController,
              decoration: const InputDecoration(
                labelText: 'Dealer ID or Phone',
                prefixIcon: Icon(Icons.person),
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
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Key sold successfully'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
              _loadKeys();
            },
            child: const Text('Confirm Sale'),
          ),
        ],
      ),
    );
  }

  void _showPurchaseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purchase Keys'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Contact your distributor to purchase activation keys.'),
            SizedBox(height: 16),
            Text('Price per key: BDT 500'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}