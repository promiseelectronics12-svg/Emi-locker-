import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../auth/presentation/screens/password_change_screen.dart';
import 'dealer_management_screen.dart';
import 'key_inventory_screen.dart';

class ResellerDashboard extends StatefulWidget {
  const ResellerDashboard({super.key});

  @override
  State<ResellerDashboard> createState() => _ResellerDashboardState();
}

class _ResellerDashboardState extends State<ResellerDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _ResellerHomeTab(),
          DealerManagementScreen(),
          KeyInventoryScreen(),
          _ResellerProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.store), label: 'Dealers'),
          NavigationDestination(icon: Icon(Icons.vpn_key), label: 'Keys'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _ResellerHomeTab extends StatefulWidget {
  const _ResellerHomeTab();

  @override
  State<_ResellerHomeTab> createState() => _ResellerHomeTabState();
}

class _ResellerHomeTabState extends State<_ResellerHomeTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final response = await Injection.apiClient.get('/api/v1/reseller/stats');
      setState(() {
        _stats = response.data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EMI Locker Reseller')),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final name = state is Authenticated
                      ? state.user.name
                      : 'Reseller';
                  return Text(
                    'Welcome, $name',
                    style: Theme.of(context).textTheme.headlineSmall,
                  );
                },
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _ResellerStatCard(
                      title: 'Total Dealers',
                      value: '${_stats?['total_dealers'] ?? 0}',
                      icon: Icons.store,
                      color: const Color(0xFF1A73E8),
                    ),
                    _ResellerStatCard(
                      title: 'Active Dealers',
                      value: '${_stats?['active_dealers'] ?? 0}',
                      icon: Icons.check_circle,
                      color: const Color(0xFF34A853),
                    ),
                    _ResellerStatCard(
                      title: 'Total Keys',
                      value: '${_stats?['total_keys'] ?? 0}',
                      icon: Icons.vpn_key,
                      color: const Color(0xFFFBBC04),
                    ),
                    _ResellerStatCard(
                      title: 'Available Keys',
                      value: '${_stats?['available_keys'] ?? 0}',
                      icon: Icons.key,
                      color: const Color(0xFF9C27B0),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Actions',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(
                            Icons.person_add,
                            color: Color(0xFF1A73E8),
                          ),
                          title: const Text('Activate New Dealer'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => _currentIndex = 1),
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.add_box,
                            color: Color(0xFF34A853),
                          ),
                          title: const Text('Add Activation Keys'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => _currentIndex = 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResellerStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ResellerStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResellerProfileTab extends StatelessWidget {
  const _ResellerProfileTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state is Authenticated ? state.user : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        child: Text(
                          user?.name.substring(0, 1).toUpperCase() ?? 'R',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? 'Reseller',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              user?.email ?? '',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('Change Password'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PasswordChangeScreen(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.help_outline),
                      title: const Text('Help & Support'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () =>
                    context.read<AuthBloc>().add(const LogoutRequested()),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text(
                  'Logout',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
