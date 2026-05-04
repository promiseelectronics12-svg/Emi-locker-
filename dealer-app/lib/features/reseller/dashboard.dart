import 'package:flutter/material.dart';

class ResellerDashboard extends StatelessWidget {
  const ResellerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reseller Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Manage Dealers'),
            leading: const Icon(Icons.people),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Activation Keys'),
            leading: const Icon(Icons.vpn_key),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Regional Sales'),
            leading: const Icon(Icons.analytics),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
