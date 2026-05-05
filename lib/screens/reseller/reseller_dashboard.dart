import 'package:flutter/material.dart';
import '../../services/reseller/reseller_service.dart';
import '../../models/reseller/reseller_models.dart';
import 'dealer_management_screen.dart';
import 'key_request_screen.dart';

class ResellerDashboard extends StatefulWidget {
  const ResellerDashboard({super.key});

  @override
  State<ResellerDashboard> createState() => _ResellerDashboardState();
}

class _ResellerDashboardState extends State<ResellerDashboard> {
  final ResellerService _service = ResellerService();
  late Future<List<Dealer>> _dealersFuture;
  late Future<KeyInventory> _inventoryFuture;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _dealersFuture = _service.getDealers();
      _inventoryFuture = _service.getKeyInventory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reseller Dashboard'),
        actions: [
          IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInventorySection(),
            const SizedBox(height: 24),
            const Text('Dealer Network', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildDealerList(),
            const SizedBox(height: 24),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildInventorySection() {
    return FutureBuilder<KeyInventory>(
      future: _inventoryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Text('Error loading inventory: ${snapshot.error}');
        final inv = snapshot.data!;
        double progress = inv.usedThisMonth / inv.monthlyQuota;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Key Inventory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _inventoryItem('Purchased', inv.purchased),
                    _inventoryItem('Assigned', inv.assigned),
                    _inventoryItem('Available', inv.available),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Monthly Quota: ${inv.usedThisMonth} / ${inv.monthlyQuota}'),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                  color: progress > 0.9 ? Colors.red : Colors.blue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _inventoryItem(String label, int value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDealerList() {
    return FutureBuilder<List<Dealer>>(
      future: _dealersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Text('Error loading dealers: ${snapshot.error}');
        final dealers = snapshot.data!;
        if (dealers.isEmpty) return const Text('No dealers found');

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dealers.length,
          itemBuilder: (context, index) {
            final dealer = dealers[index];
            return ListTile(
              title: Text(dealer.name),
              subtitle: Text('${dealer.shopName} • ${dealer.status}'),
              trailing: _buildStatusBadge(dealer.status),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DealerManagementScreen(dealer: dealer))),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'Active': color = Colors.green; break;
      case 'Suspended': color = Colors.orange; break;
      case 'Pending': color = Colors.blue; break;
      default: color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KeyRequestScreen())),
            child: const Text('Request Keys'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DealerManagementScreen(dealer: null))), // View all pending
            child: const Text('Manage Dealers'),
          ),
        ),
      ],
    );
  }
}
