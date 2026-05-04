import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/models/activation_key_model.dart';

class GenerateKeysScreen extends StatefulWidget {
  const GenerateKeysScreen({super.key});

  @override
  State<GenerateKeysScreen> createState() => _GenerateKeysScreenState();
}

class _GenerateKeysScreenState extends State<GenerateKeysScreen> {
  final _formKey = GlobalKey<FormState>();
  int _quantity = 1;
  bool _isGenerating = false;
  List<ActivationKey> _generatedKeys = [];

  Future<void> _generateKeys() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
      _generatedKeys = [];
    });

    await Future.delayed(const Duration(seconds: 1));

    final keys = List.generate(
      _quantity,
      (index) => ActivationKey(
        id: 'key_${DateTime.now().millisecondsSinceEpoch}_$index',
        resellerId: 'reseller_123',
        keyCode: _generateRandomKey(),
        status: 'AVAILABLE',
        createdAt: DateTime.now(),
      ),
    );

    setState(() {
      _isGenerating = false;
      _generatedKeys = keys;
    });
  }

  String _generateRandomKey() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    String key = '';
    for (var i = 0; i < 16; i++) {
      key += chars[(random + i * 7) % chars.length];
    }
    return 'EMI-${key.substring(0, 4)}-${key.substring(4, 8)}-${key.substring(8, 12)}-${key.substring(12, 16)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Keys'),
        backgroundColor: AppTheme.resellerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Generate Activation Keys',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Generate activation keys to sell to your dealers.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        value: _quantity,
                        decoration: const InputDecoration(
                          labelText: 'Number of Keys',
                          prefixIcon: Icon(Icons.numbers),
                        ),
                        items: [1, 5, 10, 25, 50, 100].map((value) {
                          return DropdownMenuItem(
                            value: value,
                            child: Text(value.toString()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _quantity = value ?? 1;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _generateKeys,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.resellerColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.vpn_key),
                          label: Text(_isGenerating ? 'Generating...' : 'Generate Keys'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_generatedKeys.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Generated Keys',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...(_generatedKeys.map((key) => Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.key, color: AppTheme.successColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  key.keyCode,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Key copied to clipboard'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: QrImageView(
                                  data: key.keyCode,
                                  version: QrVersions.auto,
                                  size: 100,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status: ${key.status}',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Created: ${_formatDate(key.createdAt)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ))),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All keys exported'),
                    ),
                  );
                },
                icon: const Icon(Icons.share),
                label: const Text('Export All Keys'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}