import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/auth_bloc.dart';
import 'dealer_screens/device_dashboard_screen.dart';
import 'enroll_device_screen.dart';
import 'analytics_screen.dart';
import 'neir_export_screen.dart';
import 'key_inventory_screen.dart';

class DealerHome extends StatefulWidget {
  const DealerHome({super.key});

  @override
  State<DealerHome> createState() => _DealerHomeState();
}

class _DealerHomeState extends State<DealerHome> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DeviceDashboardScreen(),
    const NeirExportScreen(), // Using this as device list for now as it shows devices
    const KeyInventoryScreen(),
    const AnalyticsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      floatingActionButton: _selectedIndex == 0
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EnrollDeviceScreen()),
            ),
            label: const Text('Enroll Device'),
            icon: const Icon(Icons.add),
          )
        : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.devices), label: 'NEIR/Devices'),
          NavigationDestination(icon: Icon(Icons.vpn_key), label: 'Keys'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Analytics'),
        ],
      ),
    );
  }
}
