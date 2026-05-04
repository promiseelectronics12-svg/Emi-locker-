import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/auth_bloc.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/common_widgets.dart';
import 'reseller_dashboard_tab.dart';
import 'dealer_management_screen.dart';
import 'key_request_screen.dart';
import 'key_inventory_screen.dart';

class ResellerHomeScreen extends StatefulWidget {
  const ResellerHomeScreen({super.key});

  @override
  State<ResellerHomeScreen> createState() => _ResellerHomeScreenState();
}

class _ResellerHomeScreenState extends State<ResellerHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const ResellerDashboardTab(),
    const DealerManagementScreen(),
    const KeyRequestScreen(),
    const _ResellerSettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label: 'Dealers',
          ),
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Keys',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ResellerSettingsTab extends StatelessWidget {
  const _ResellerSettingsTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppTheme.resellerColor,
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state.user;
          return ListView(
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(
                  color: AppTheme.resellerColor,
                ),
                accountName: Text(user?.name ?? ''),
                accountEmail: Text(user?.email ?? ''),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    (user?.name ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 32,
                      color: AppTheme.resellerColor,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.lock),
                title: const Text('Change Password'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pushNamed(context, '/change-password');
                },
              ),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('2FA Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pushNamed(context, '/2fa-setup');
                },
              ),
              ListTile(
                leading: const Icon(Icons.business),
                title: const Text('Company Info'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: AppTheme.errorColor),
                title: const Text('Logout', style: TextStyle(color: AppTheme.errorColor)),
                onTap: () async {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Logout',
                    message: 'Are you sure you want to logout?',
                    confirmText: 'Logout',
                    confirmColor: AppTheme.errorColor,
                  );
                  if (confirm && context.mounted) {
                    context.read<AuthBloc>().add(AuthLogoutRequested());
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}