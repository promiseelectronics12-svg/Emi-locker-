import 'package:flutter/material.dart';
import '../../../shared/models/user.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';

class AllocateKeysScreen extends StatefulWidget {
  final User dealer;

  const AllocateKeysScreen({super.key, required this.dealer});

  @override
  State<AllocateKeysScreen> createState() => _AllocateKeysScreenState();
}

class _AllocateKeysScreenState extends State<AllocateKeysScreen> {
  final ApiClient _apiClient = ApiClient();
  int _keysToAllocate = 0;
  bool _isLoading = false;
  int _availableKeys = 0;

  @override
  void initState() {
    super.initState();
    _loadAvailableKeys();
  }

  Future<void> _loadAvailableKeys() async {
    try {
      final response = await _apiClient.get('/reseller/analytics');
      if (response.statusCode == 200) {
        setState(() {
          _availableKeys = response.data['available_keys'] ?? 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load key balance'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _allocateKeys() async {
    if (_keysToAllocate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select number of keys to allocate'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }

    if (_keysToAllocate > _availableKeys) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient keys available'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.post('/reseller/keys/allocate', data: {
        'dealer_id': widget.dealer.id,
        'quantity': _keysToAllocate,
      });

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Allocated $_keysToAllocate keys to ${widget.dealer.name}'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.data['message'] ?? 'Allocation failed'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Allocation failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Allocate Keys'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.primaryLight,
                      child: Text(
                        widget.dealer.name.isNotEmpty
                            ? widget.dealer.name[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.dealer.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          if (widget.dealer.shopName != null)
                            Text(
                              widget.dealer.shopName!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.vpn_key,
                                size: 16,
                                color: AppTheme.accentColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Current: ${widget.dealer.availableKeys} keys',
                                style: const TextStyle(
                                  color: AppTheme.accentColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Key Balance',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.vpn_key,
                          size: 48,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '$_availableKeys',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'keys available',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keys to Allocate',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _keysToAllocate > 0
                              ? () => setState(() => _keysToAllocate--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          iconSize: 36,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 24),
                        Text(
                          '$_keysToAllocate',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          onPressed: _keysToAllocate < _availableKeys
                              ? () => setState(() => _keysToAllocate++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                          iconSize: 36,
                          color: AppTheme.primaryColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [5, 10, 20, 50].map((qty) {
                        return ActionChip(
                          label: Text('+$qty'),
                          onPressed: _keysToAllocate + qty <= _availableKeys
                              ? () => setState(() => _keysToAllocate += qty)
                              : null,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: AppTheme.primaryColor.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'After allocation, dealer will have ${widget.dealer.availableKeys + _keysToAllocate} keys total.',
                        style: const TextStyle(
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading || _keysToAllocate <= 0
                  ? null
                  : _allocateKeys,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Allocate $_keysToAllocate Keys'),
            ),
          ],
        ),
      ),
    );
  }
}
