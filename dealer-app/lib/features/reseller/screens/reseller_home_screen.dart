import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/reseller_bloc.dart';
import '../bloc/reseller_event.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../features/auth/bloc/auth_event.dart';
import '../../../shared/models/user.dart';

class ResellerHomeScreen extends StatefulWidget {
  const ResellerHomeScreen({super.key});

  @override
  State<ResellerHomeScreen> createState() => _ResellerHomeScreenState();
}

class _ResellerHomeScreenState extends State<ResellerHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens.addAll([
      const _ResellerDashboardTab(),
      const DealerManagementScreen(),
      const KeyManagementScreen(),
      const ResellerAnalyticsScreen(),
      const ResellerSettingsScreen(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Dealers',
          ),
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Keys',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Analytics',
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

class _ResellerDashboardTab extends StatelessWidget {
  const _ResellerDashboardTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EMI Locker'),
        automaticallyImplyLeading: false,
      ),
      body: BlocListener<ResellerBloc, ResellerState>(
        listener: (context, state) {
          if (state is ResellerKeysLoaded) {
          } else if (state is ResellerOperationSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.successColor,
              ),
            );
          } else if (state is ResellerError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeCard(context),
              const SizedBox(height: 16),
              _buildQuickStats(context),
              const SizedBox(height: 16),
              _buildQuickActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) {
    return Card(
      color: AppTheme.primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: const Icon(
                Icons.business,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Reseller Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    context.read<ResellerBloc>().add(const ResellerLoadKeys());

    return BlocBuilder<ResellerBloc, ResellerState>(
      builder: (context, state) {
        int availableKeys = 0;
        int usedKeys = 0;

        if (state is ResellerKeysLoaded) {
          availableKeys = state.availableKeys;
          usedKeys = state.usedKeys;
        }

        return Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.key, color: AppTheme.primaryColor),
                      const SizedBox(height: 8),
                      Text(
                        '$availableKeys',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Text('Available'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle, color: AppTheme.successColor),
                      const SizedBox(height: 8),
                      Text(
                        '$usedKeys',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Text('Used'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.person_add,
                title: 'View Dealers',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DealerManagementScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.add_circle,
                title: 'Add Keys',
                onTap: () {
                  _showAddKeysDialog(context);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.sync,
                title: 'Transfer Keys',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const KeyManagementScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.analytics,
                title: 'Analytics',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ResellerAnalyticsScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, size: 32, color: AppTheme.primaryColor),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddKeysDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Activation Keys'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantity',
            hintText: 'Enter number of keys',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = int.tryParse(controller.text);
              if (quantity != null && quantity > 0) {
                context.read<ResellerBloc>().add(ResellerAddKeys(quantity: quantity));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class DealerManagementScreen extends StatefulWidget {
  const DealerManagementScreen({super.key});

  @override
  State<DealerManagementScreen> createState() => _DealerManagementScreenState();
}

class _DealerManagementScreenState extends State<DealerManagementScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(const ResellerLoadDealers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dealer Management'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search dealers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          context.read<ResellerBloc>().add(
                                const ResellerLoadDealers(search: null),
                              );
                        },
                      )
                    : null,
              ),
              onSubmitted: (value) {
                context.read<ResellerBloc>().add(
                      ResellerLoadDealers(search: value),
                    );
              },
            ),
          ),
          Expanded(
            child: BlocBuilder<ResellerBloc, ResellerState>(
              builder: (context, state) {
                if (state is ResellerLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is ResellerError) {
                  return EmptyStateWidget(
                    icon: Icons.error_outline,
                    title: 'Failed to load dealers',
                    subtitle: state.message,
                    action: ElevatedButton(
                      onPressed: () {
                        context.read<ResellerBloc>().add(
                              const ResellerLoadDealers(),
                            );
                      },
                      child: const Text('Retry'),
                    ),
                  );
                }

                if (state is ResellerLoaded) {
                  if (state.dealers.isEmpty) {
                    return const EmptyStateWidget(
                      icon: Icons.people,
                      title: 'No dealers found',
                      subtitle: 'Dealers will appear here once they register',
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      context.read<ResellerBloc>().add(
                            const ResellerLoadDealers(),
                          );
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: state.dealers.length,
                      itemBuilder: (context, index) {
                        final dealer = state.dealers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                              child: Text(
                                dealer.name.isNotEmpty
                                    ? dealer.name[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  color: AppTheme.primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(dealer.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dealer.shopName ?? 'No shop name'),
                                Text(
                                  dealer.phone,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'transfer',
                                  child: Row(
                                    children: [
                                      Icon(Icons.sync),
                                      SizedBox(width: 8),
                                      Text('Transfer Keys'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'suspend',
                                  child: Row(
                                    children: [
                                      Icon(Icons.block, color: AppTheme.errorColor),
                                      SizedBox(width: 8),
                                      Text('Suspend'),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'transfer') {
                                  _showTransferKeysDialog(context, dealer);
                                } else if (value == 'suspend') {
                                  _confirmSuspendDealer(context, dealer);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTransferKeysDialog(BuildContext context, User dealer) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Transfer Keys to ${dealer.name}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Keys',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = int.tryParse(controller.text);
              if (quantity != null && quantity > 0) {
                context.read<ResellerBloc>().add(
                      ResellerTransferKeys(
                        dealerId: dealer.id,
                        quantity: quantity,
                      ),
                    );
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }

  void _confirmSuspendDealer(BuildContext context, User dealer) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suspend Dealer'),
        content: Text('Are you sure you want to suspend ${dealer.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            onPressed: () {
              context.read<ResellerBloc>().add(
                    ResellerSuspendDealer(dealerId: dealer.id),
                  );
              Navigator.pop(dialogContext);
            },
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
  }
}

class KeyManagementScreen extends StatefulWidget {
  const KeyManagementScreen({super.key});

  @override
  State<KeyManagementScreen> createState() => _KeyManagementScreenState();
}

class _KeyManagementScreenState extends State<KeyManagementScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(const ResellerLoadKeys());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Key Management'),
      ),
      body: BlocBuilder<ResellerBloc, ResellerState>(
        builder: (context, state) {
          if (state is ResellerLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ResellerKeysLoaded) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.key,
                                  size: 48,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${state.availableKeys}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const Text('Available'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  '${state.usedKeys}',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const Text('Used'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  '${state.totalKeys}',
                                  style: Theme.of(context).textTheme.headlineSmall,
                                ),
                                const Text('Total'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showAddKeysDialog(context);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Generate Keys'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return const EmptyStateWidget(
            icon: Icons.key,
            title: 'No key data',
          );
        },
      ),
    );
  }

  void _showAddKeysDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generate Activation Keys'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantity',
            hintText: 'Enter number of keys to generate',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final quantity = int.tryParse(controller.text);
              if (quantity != null && quantity > 0) {
                context.read<ResellerBloc>().add(ResellerAddKeys(quantity: quantity));
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }
}

class ResellerAnalyticsScreen extends StatelessWidget {
  const ResellerAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: const Center(
        child: EmptyStateWidget(
          icon: Icons.analytics,
          title: 'Analytics coming soon',
          subtitle: 'Detailed analytics for resellers',
        ),
      ),
    );
  }
}

class ResellerSettingsScreen extends StatelessWidget {
  const ResellerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text('2FA Settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock),
                  title: const Text('Change Password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => const ConfirmationDialog(
                  title: 'Logout',
                  content: 'Are you sure you want to logout?',
                  confirmText: 'Logout',
                  confirmColor: AppTheme.errorColor,
                ),
              );

              if (confirmed == true && context.mounted) {
                context.read<AuthBloc>().add(AuthLogoutRequested());
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.errorColor,
              side: const BorderSide(color: AppTheme.errorColor),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}