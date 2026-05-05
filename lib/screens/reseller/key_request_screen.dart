import 'package:flutter/material.dart';
import '../../services/reseller/reseller_service.dart';
import '../../models/reseller/reseller_models.dart';

class KeyRequestScreen extends StatefulWidget {
  const KeyRequestScreen({super.key});

  @override
  State<<KeyKeyRequestScreen> createState() => _KeyRequestScreenState();
}

class _KeyRequestScreenState extends State<<KeyKeyRequestScreen> {
  final ResellerService _service = ResellerService();
  final _qtyController = TextEditingController();
  final _justificationController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Key Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRequestForm(),
            const SizedBox(height: 32),
            const Text('Request History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildRequestList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request New Keys', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyController,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
                hintText: 'Enter number of keys',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _justificationController,
              decoration: const InputDecoration(
                labelText: 'Justification',
                border: OutlineInputBorder(),
                hintText: 'Why are these keys needed?',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                child: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Text('Submit Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<<voidvoid> _submitRequest() async {
    final qty = int.tryParse(_qtyController.text);
    final justification = _justificationController.text.trim();

    if (qty == null || qty <= 0) {
      _showError('Please enter a valid quantity');
      return;
    }
    if (justification.isEmpty) {
      _showError('Justification is required');
      return;
    }

    // Client-side validation: max 20% of monthly quota
    // We fetch the current inventory to validate
    try {
      final inv = await _service.getKeyInventory();
      final maxRequest = (inv.monthlyQuota * 0.2).floor();
      if (qty > maxRequest) {
        _showError('Single request cannot exceed 20% of monthly quota ($maxRequest keys)');
        return;
      }

      setState(() => _isLoading = true);
      await _service.requestKeys(qty, justification);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request submitted successfully')),
      );
      _qtyController.clear();
      _justificationController.clear();
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRequestList() {
    return FutureBuilder<<ListList<<KeyKeyRequest>>(
      future: _service.getKeyRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error loading requests: ${snapshot.error}');
        }
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return const Text('No requests found');
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return ListTile(
              title: Text('Request for ${req.quantity} keys'),
              subtitle: Text('${req.status} • ${req.createdAt.toString().split(' ')[0]}'),
              trailing: _buildStatusIcon(req.status),
              onTap: () => _showRequestDetails(req),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(String status) {
    Color color;
    IconData icon;
    switch (status) {
      case 'Approved': color = Colors.green; icon = Icons.check_circle; break;
      case 'Rejected': color = Colors.red; icon = Icons.cancel; break;
      case 'Pending': color = Colors.orange; icon = Icons.hourglass_empty; break;
      default: color = Colors.grey; icon = Icons.help;
    }
    return Icon(icon, color: color);
  }

  void _showRequestDetails(KeyRequest req) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quantity: ${req.quantity}'),
            const SizedBox(height: 8),
            Text('Status: ${req.status}'),
            const SizedBox(height: 8),
            const Text('Justification:'),
            Text(req.justification),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
