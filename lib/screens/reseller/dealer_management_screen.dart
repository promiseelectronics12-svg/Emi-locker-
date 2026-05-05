import 'package:flutter/material.dart';
import '../../services/reseller/reseller_service.dart';
import '../../models/reseller/reseller_models.dart';

class DealerManagementScreen extends StatefulWidget {
  final Dealer? dealer;

  const DealerManagementScreen({super.key, this.dealer});

  @override
  State<<DealerDealerManagementScreen> createState() => _DealerManagementScreenState();
}

class _DealerManagementScreenState extends State<<DealerDealerManagementScreen> {
  final ResellerService _service = ResellerService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    if (widget.dealer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dealer Management')),
        body: _buildDealerList(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.dealer!.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailsSection(),
            const SizedBox(height: 24),
            _buildPerformanceSection(),
            const SizedBox(height: 24),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    final d = widget.dealer!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Application Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            _detailRow('Shop Name', d.shopName),
            _detailRow('Phone', d.phone),
            _detailRow('Status', d.status),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
    final d = widget.dealer!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Performance Metrics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _perfMetric('Activation', d.activationRate),
                _perfMetric('Collection', d.collectionRate),
                _perfMetric('Keys Used', d.keysUsed.toDouble()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _perfMetric(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value.toStringAsFixed(1) + (label == 'Keys Used' ? '' : '%'), 
             style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showStatusDialog('Approved'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: const Text('Approve'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showStatusDialog('Rejected'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Reject'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _showAssignKeysDialog(),
            child: const Text('Assign Activation Keys'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _showStatusDialog('Suspended'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Suspend Dealer'),
          ),
        ),
      ],
    );
  }

  void _showStatusDialog(String status) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set Status to $status'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                await _service.updateDealerStatus(widget.dealer!.id, status, reason: reasonController.text);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dealer $status successfully')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showAssignKeysDialog() {
    final qtyController = TextEditingController();
    final tfaController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign Keys'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyController, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: TextInputType.number),
            TextField(controller: tfaController, decoration: const InputDecoration(labelText: '2FA Verification Code')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text);
              if (qty == null || qty <= 0) return;
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                await _service.assignKeys(widget.dealer!.id, qty, tfaController.text);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keys assigned successfully')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }

  Widget _buildDealerList() {
    return FutureBuilder<<ListList<<DealerDealer>>(
      future: _service.getDealers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final dealers = snapshot.data ?? [];
        return ListView.builder(
          itemCount: dealers.length,
          itemBuilder: (context, index) {
            final dealer = dealers[index];
            return ListTile(
              title: Text(dealer.name),
              subtitle: Text(dealer.status),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DealerManagementScreen(dealer: dealer))),
            );
          },
        );
      },
    );
  }
}
