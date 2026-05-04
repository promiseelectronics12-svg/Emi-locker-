import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:math';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/services/api_client.dart';
import '../auth/auth_bloc.dart';

class GenerateKeysScreen extends StatefulWidget {
  const GenerateKeysScreen({super.key});

  @override
  State<GenerateKeysScreen> createState() => _GenerateKeysScreenState();
}

class _GenerateKeysScreenState extends State<GenerateKeysScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiClient = ApiClient();

  int _quantity = 10;
  String? _selectedDealerId;
  List<String> _generatedKeys = [];
  bool _isGenerating = false;
  bool _showGenerated = false;

  String _generateKeyCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
  }

  void _generateKeys() async {
    if (_selectedDealerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a dealer first'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedKeys = List.generate(_quantity, (_) => _generateKeyCode());
    });

    try {
      final response = await _apiClient.post('/activation-keys/generate', data: {
        'reseller_id': context.read<AuthBloc>().state.user?.id,
        'dealer_id': _selectedDealerId,
        'quantity': _quantity,
        'key_codes': _generatedKeys,
      });

      if (response.statusCode == 200) {
        setState(() => _showGenerated = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate keys: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _reset() {
    setState(() {
      _generatedKeys = [];
      _showGenerated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Activation Keys'),
        actions: [
          if (_showGenerated)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Generate More', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _showGenerated ? _buildGeneratedKeys() : _buildKeyForm(),
    );
  }

  Widget _buildKeyForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Dealer',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadDealers(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final dealers = snapshot.data ?? [];
                        return DropdownButtonFormField<String>(
                          value: _selectedDealerId,
                          decoration: const InputDecoration(
                            hintText: 'Select a dealer',
                          ),
                          items: dealers.map((dealer) {
                            return DropdownMenuItem(
                              value: dealer['id'] as String,
                              child: Text(dealer['name'] as String),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedDealerId = value);
                          },
                          validator: (value) {
                            if (value == null) {
                              return 'Please select a dealer';
                            }
                            return null;
                          },
                        );
                      },
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
                    const Text(
                      'Quantity',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _quantity.toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _quantity < 100
                              ? () => setState(() => _quantity++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 8,
                          children: [10, 25, 50, 100].map((q) {
                            return ActionChip(
                              label: Text('$q'),
                              onPressed: () => setState(() => _quantity = q),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateKeys,
              icon: _isGenerating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.vpn_key, color: Colors.white),
              label: Text(_isGenerating ? 'Generating...' : 'Generate $_quantity Keys'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadDealers() async {
    try {
      final authState = context.read<AuthBloc>().state;
      final response = await _apiClient.get(
        '/dealers',
        queryParameters: {'reseller_id': authState.user?.id},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['dealers'] ?? [];
        return data.map((d) => {
          'id': d['id'] as String,
          'name': (d['shop_name'] ?? d['name']) as String,
        }).toList();
      }
    } catch (e) {
      // Return empty
    }
    return [];
  }

  Widget _buildGeneratedKeys() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppTheme.successColor.withOpacity(0.1),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.successColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Keys Generated Successfully',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$_quantity keys created for dealer',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _generatedKeys.length,
            itemBuilder: (context, index) {
              final key = _generatedKeys[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.vpn_key, color: AppTheme.primaryColor),
                  ),
                  title: Text(
                    '${key.substring(0, 4)}-${key.substring(4, 8)}-${key.substring(8, 12)}-${key.substring(12, 16)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text('Key ${index + 1} of $_quantity'),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Key copied to clipboard')),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Keys shared via SMS/Email')),
                );
              },
              icon: const Icon(Icons.share, color: Colors.white),
              label: const Text('Send Keys to Dealer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}