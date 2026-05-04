import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/auth_bloc.dart';
import 'reseller_dashboard_screen.dart';
import 'dealers_list_screen.dart';
import 'generate_keys_screen.dart';

class ResellerHome extends StatefulWidget {
  const ResellerHome({super.key});

  @override
  State<ResellerHome> createState() => _ResellerHomeState();
}

class _ResellerHomeState extends State<ResellerHome> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const ResellerDashboardScreen(),
    const DealersListScreen(),
    const GenerateKeysScreen(),
    const Center(child: Text('Settings & Profile')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.store), label: 'Dealers'),
          NavigationDestination(icon: Icon(Icons.key_sharp), label: 'Keys'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Settings'),
        ],
      ),
    );
  }
}
