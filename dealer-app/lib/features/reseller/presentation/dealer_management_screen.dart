import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';

class DealerManagementScreen extends StatefulWidget {
  const DealerManagementScreen({super.key});

  @override
  State<DealerManagementScreen> createState() => _DealerManagementScreenState();
}

class _DealerManagementScreenState extends State<DealerManagementScreen> {
  List<Map<String, dynamic>> _dealers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDealers();
  }

  Future<void> _loadDealers() async {
    try {
      final response = await Injection.apiClient.get(
        '/api/v1/reseller/dealers',
      );
      setState(() {
        _dealers = List<Map<String, dynamic>>.from(response.data);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealer Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showActivateDealerDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dealers.isEmpty
          ? const Center(child: Text('No dealers activated yet'))
          : RefreshIndicator(
              onRefresh: _loadDealers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _dealers.length,
                itemBuilder: (context, index) {
                  final dealer = _dealers[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (dealer['name'] ?? 'D').substring(0, 1).toUpperCase(),
                        ),
                      ),
                      title: Text(dealer['name'] ?? ''),
                      subtitle: Text(
                        dealer['shop_name'] ?? dealer['email'] ?? '',
                      ),
                      trailing: Chip(
                        label: Text(
                          dealer['status'] ?? 'active',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: dealer['status'] == 'active'
                            ? Colors.green
                            : Colors.orange,
                        padding: EdgeInsets.zero,
                      ),
                      onTap: () => _showDealerDetail(dealer),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _showActivateDealerDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final shopNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activate New Dealer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Dealer Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: shopNameController,
                decoration: const InputDecoration(labelText: 'Shop Name'),
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
              try {
                await Injection.apiClient.post(
                  '/api/v1/reseller/dealers',
                  data: {
                    'name': nameController.text,
                    'email': emailController.text,
                    'phone': phoneController.text,
                    'shop_name': shopNameController.text,
                  },
                );
                Navigator.pop(context);
                _loadDealers();
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Failed: $e')));
              }
            },
            child: const Text('Activate'),
          ),
        ],
      ),
    );
  }

  void _showDealerDetail(Map<String, dynamic> dealer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                dealer['name'] ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                dealer['email'] ?? '',
                style: const TextStyle(color: Colors.grey),
              ),
              const Divider(),
              _detailRow('Shop Name', dealer['shop_name'] ?? '-'),
              _detailRow('Phone', dealer['phone'] ?? '-'),
              _detailRow('Status', dealer['status'] ?? 'active'),
              _detailRow('Activated', dealer['created_at'] ?? '-'),
              const SizedBox(height: 16),
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Divider(),
              _detailRow('Total Devices', '${dealer['total_devices'] ?? 0}'),
              _detailRow('Active Devices', '${dealer['active_devices'] ?? 0}'),
              _detailRow('Keys Remaining', '${dealer['keys_remaining'] ?? 0}'),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
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
