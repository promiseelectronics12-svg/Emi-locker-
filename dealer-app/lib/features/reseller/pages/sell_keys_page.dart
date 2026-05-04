import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/models/user.dart';

class SellKeysPage extends StatefulWidget {
  final User? preselectedDealer;

  const SellKeysPage({super.key, this.preselectedDealer});

  @override
  State<SellKeysPage> createState() => _SellKeysPageState();
}

class _SellKeysPageState extends State<SellKeysPage> {
  final ApiClient _apiClient = ApiClient();
  final _formKey = GlobalKey<FormState>();
  final _dealerPhoneController = TextEditingController();
  final _quantityController = TextEditingController();

  List<User> _dealers = [];
  User? _selectedDealer;
  int _availableKeys = 0;
  int _quantity = 1;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedDealer != null) {
      _selectedDealer = widget.preselectedDealer;
      _dealerPhoneController.text = widget.preselectedDealer!.phone;
    }
    _loadData();
  }

  @override
  void dispose() {
    _dealerPhoneController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/reseller/dealers');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['dealers'] as List<dynamic>;
        setState(() {
          _dealers = data
              .map((json) => User.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }

      final keysResponse = await _apiClient.get('/reseller/keys/available');
      if (keysResponse.statusCode == 200) {
        setState(() {
          _availableKeys = keysResponse.data['count'] as int? ?? 0;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load data';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _searchDealer(String phone) {
    final dealer = _dealers.firstWhere(
      (d) => d.phone == phone,
      orElse: () => User(
        id: '',
        name: '',
        email: '',
        phone: '',
        shopName: '',
        tradeLicense: '',
        address: '',
        role: UserRole.dealer,
        createdAt: DateTime.now(),
      ),
    );

    if (dealer.id.isNotEmpty) {
      setState(() => _selectedDealer = dealer);
    } else {
      setState(() => _selectedDealer = null);
    }
  }

  void _incrementQuantity() {
    if (_quantity < _availableKeys) {
      setState(() => _quantity++);
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() => _quantity--);
    }
  }

  Future<void> _processSale() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDealer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid dealer'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final response = await _apiClient.post('/reseller/keys/sell', data: {
        'dealer_id': _selectedDealer!.id,
        'quantity': _quantity,
      });

      if (response.statusCode == 200) {
        final keys = (response.data['keys'] as List<dynamic>)
            .map((k) => k as String)
            .toList();

        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: AppTheme.successColor),
                  SizedBox(width: 8),
                  Text('Sale Complete'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sold $_quantity key(s) to ${_selectedDealer!.name}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Keys:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: keys.length,
                      itemBuilder: (context, index) {
                        return Text(
                          keys[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sale failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell Keys'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Available Keys',
                              style: TextStyle(
                                color: AppTheme.textSecondaryColor,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$_availableKeys',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Select Dealer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _dealerPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'Dealer Phone Number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '01XXX-XXXXXX',
                      ),
                      keyboardType: TextInputType.phone,
                      onChanged: _searchDealer,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter dealer phone number';
                        }
                        return null;
                      },
                    ),
                    if (_selectedDealer != null) ...[
                      const SizedBox(height: 16),
                      Card(
                        color: AppTheme.successColor.withOpacity(0.1),
                        child: ListTile(
                          leading: const Icon(
                            Icons.check_circle,
                            color: AppTheme.successColor,
                          ),
                          title: Text(_selectedDealer!.name),
                          subtitle: Text(_selectedDealer!.shopName),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      'Quantity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: _quantity > 1 ? _decrementQuantity : null,
                          icon: const Icon(Icons.remove),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton.outlined(
                          onPressed:
                              _quantity < _availableKeys ? _incrementQuantity : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Max: $_availableKeys keys',
                      style: const TextStyle(
                        color: AppTheme.textSecondaryColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _processSale,
                        child: _isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Sell $_quantity Key(s)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}