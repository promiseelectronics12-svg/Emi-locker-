import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';

class KeyInventoryScreen extends StatefulWidget {
  const KeyInventoryScreen({super.key});

  @override
  State<KeyInventoryScreen> createState() => _KeyInventoryScreenState();
}

class _KeyInventoryScreenState extends State<KeyInventoryScreen> {
  List<Map<String, dynamic>> _keys = [];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    try {
      final query = _filter == 'all' ? '' : '?status=$_filter';
      final response = await Injection.apiClient.get('/api/v1/keys/my$query');
      setState(() {
        _keys = List<Map<String, dynamic>>.from(response.data);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _keys.where((k) => k['status'] == 'available').length;
    final used = _keys.where((k) => k['status'] == 'used').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activation Keys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddKeysDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          'Total',
                          '${_keys.length}',
                          const Color(0xFF1A73E8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _summaryCard(
                          'Available',
                          '$available',
                          const Color(0xFF34A853),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _summaryCard(
                          'Used',
                          '$used',
                          const Color(0xFFEA4335),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('All')),
                      ButtonSegment(
                        value: 'available',
                        label: Text('Available'),
                      ),
                      ButtonSegment(value: 'used', label: Text('Used')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (val) {
                      setState(() => _filter = val.first);
                      _loadKeys();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadKeys,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _keys.length,
                      itemBuilder: (context, index) {
                        final key = _keys[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              key['status'] == 'available'
                                  ? Icons.vpn_key
                                  : Icons.key_off,
                              color: key['status'] == 'available'
                                  ? const Color(0xFF34A853)
                                  : Colors.grey,
                            ),
                            title: Text(
                              key['key'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              key['status'] == 'used'
                                  ? 'Used by: ${key['used_by_device_id'] ?? 'Unknown'}'
                                  : 'Available',
                            ),
                            trailing: Chip(
                              label: Text(
                                key['status'] ?? 'unknown',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: key['status'] == 'available'
                                  ? const Color(0xFF34A853)
                                  : Colors.grey,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddKeysDialog() {
    final keysController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Activation Keys'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter keys, one per line:'),
              const SizedBox(height: 8),
              TextField(
                controller: keysController,
                decoration: const InputDecoration(
                  hintText: 'KEY-XXXX-XXXX\nKEY-YYYY-YYYY',
                  border: OutlineInputBorder(),
                ),
                maxLines: 10,
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
            onPressed: () async {
              final keys = keysController.text
                  .split('\n')
                  .map((k) => k.trim())
                  .where((k) => k.isNotEmpty)
                  .toList();
              if (keys.isEmpty) return;

              try {
                await Injection.apiClient.post(
                  '/api/v1/keys',
                  data: {'keys': keys},
                );
                Navigator.pop(context);
                _loadKeys();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${keys.length} keys added')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            child: const Text('Add Keys'),
          ),
        ],
      ),
    );
  }
}
