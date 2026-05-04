import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';

class BuyKeysScreen extends StatefulWidget {
  const BuyKeysScreen({super.key});

  @override
  State<BuyKeysScreen> createState() => _BuyKeysScreenState();
}

class _BuyKeysScreenState extends State<BuyKeysScreen> {
  final ApiClient _apiClient = ApiClient();
  int _selectedQuantity = 10;
  final _formKey = GlobalKey<FormState>();
  final _transactionIdController = TextEditingController();
  bool _isLoading = false;

  final Map<int, double> _pricing = {
    10: 8.0,
    50: 7.5,
    100: 7.0,
    500: 6.0,
    1000: 5.0,
  };

  double get _pricePerKey => _pricing[_selectedQuantity] ?? 8.0;
  double get _totalCost => _selectedQuantity * _pricePerKey;

  @override
  void dispose() {
    _transactionIdController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.post('/reseller/keys/order', data: {
        'quantity': _selectedQuantity,
        'transaction_id': _transactionIdController.text.trim(),
      });

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order submitted successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response.data['message'] ?? 'Order failed'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order failed'),
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
        title: const Text('Buy Activation Keys'),
      ),
      body: SingleChildScrollView(
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
                      Text(
                        'Select Quantity',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _pricing.keys.map((qty) {
                          final isSelected = _selectedQuantity == qty;
                          return ChoiceChip(
                            label: Text('$qty keys'),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() => _selectedQuantity = qty);
                            },
                            selectedColor: AppTheme.primaryColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textPrimary,
                            ),
                          );
                        }).toList(),
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
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Price per key:'),
                          Text(
                            '৳${_pricePerKey.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Quantity:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '$_selectedQuantity',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total:',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '৳${_totalCost.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
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
                        'Payment Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'bKash/Nagad Merchant Account',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text('01XXXXXXXXX'),
                            SizedBox(height: 8),
                            Text(
                              'Send money and enter the transaction ID below.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _transactionIdController,
                        decoration: const InputDecoration(
                          labelText: 'Transaction ID *',
                          prefixIcon: Icon(Icons.receipt_outlined),
                          hintText: 'Enter bKash/Nagad transaction ID',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter transaction ID';
                          }
                          if (value.length < 8) {
                            return 'Invalid transaction ID';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitOrder,
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
                    : const Text('Submit Order'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
