import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../bloc/reseller_bloc.dart';

class ResellerDashboardScreen extends StatefulWidget {
  const ResellerDashboardScreen({super.key});

  @override
  State<ResellerDashboardScreen> createState() => _ResellerDashboardScreenState();
}

class _ResellerDashboardScreenState extends State<ResellerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(LoadResellerAnalytics());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ResellerBloc, ResellerState>(
      builder: (context, state) {
        if (state.isLoading && state.resellerAnalytics == null) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading dashboard...'),
          );
        }

        final analytics = state.resellerAnalytics;

        return RefreshIndicator(
          onRefresh: () async {
            context.read<ResellerBloc>().add(LoadResellerAnalytics());
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back!',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your dealers and key inventory',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondaryColor,
                      ),
                ),
                const SizedBox(height: 24),
                if (analytics != null) ...[
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      ProgressCard(
                        title: 'Total Dealers',
                        value: analytics.totalDealers.toString(),
                        icon: Icons.store,
                        color: AppTheme.primaryColor,
                      ),
                      ProgressCard(
                        title: 'Active Dealers',
                        value: analytics.activeDealers.toString(),
                        icon: Icons.check_circle,
                        color: AppTheme.successColor,
                      ),
                      ProgressCard(
                        title: 'Available Keys',
                        value: analytics.availableKeys.toString(),
                        icon: Icons.vpn_key,
                        color: AppTheme.warningColor,
                      ),
                      ProgressCard(
                        title: 'Sold Keys',
                        value: analytics.soldKeys.toString(),
                        icon: Icons.sell,
                        color: AppTheme.secondaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressCard(
                          title: 'Total Devices',
                          value: analytics.totalDevices.toString(),
                          icon: Icons.phone_android,
                          color: Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ProgressCard(
                          title: 'Revenue',
                          value: '৳${_formatNumber(analytics.totalRevenue)}',
                          icon: Icons.attach_money,
                          color: AppTheme.successColor,
                        ),
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
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _QuickActionButton(
                                  icon: Icons.store_outlined,
                                  label: 'View Dealers',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/reseller/dealers',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _QuickActionButton(
                                  icon: Icons.vpn_key,
                                  label: 'Key Inventory',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/reseller/keys',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _QuickActionButton(
                                  icon: Icons.add_chart,
                                  label: 'Generate Keys',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/reseller/generate-keys',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (state.error != null) ...[
                  ErrorDisplayWidget(
                    message: state.error!,
                    onRetry: () => context.read<ResellerBloc>().add(LoadResellerAnalytics()),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatNumber(double number) {
    if (number >= 10000000) {
      return '${(number / 10000000).toStringAsFixed(1)}Cr';
    } else if (number >= 100000) {
      return '${(number / 100000).toStringAsFixed(1)}L';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toStringAsFixed(0);
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primaryColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class DealersListScreen extends StatefulWidget {
  const DealersListScreen({super.key});

  @override
  State<DealersListScreen> createState() => _DealersListScreenState();
}

class _DealersListScreenState extends State<DealersListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(const LoadDealers());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ResellerBloc, ResellerState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '${state.totalDealers} Dealers',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GenerateKeysScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Generate Keys'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.isLoading && state.dealers.isEmpty
                  ? const LoadingWidget(message: 'Loading dealers...')
                  : state.dealers.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.store,
                          title: 'No Dealers',
                          subtitle: 'Your authorized dealers will appear here',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            context.read<ResellerBloc>().add(const LoadDealers());
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: state.dealers.length,
                            itemBuilder: (context, index) {
                              final dealer = state.dealers[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  child: InkWell(
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/reseller/dealer/${dealer.id}',
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                AppTheme.primaryColor.withOpacity(0.1),
                                            child: const Icon(
                                              Icons.store,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  dealer.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  dealer.shopName,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: AppTheme
                                                            .textSecondaryColor,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${dealer.activeDevices}/${dealer.totalDevices} devices',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                          StatusBadge(status: dealer.status),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class KeyInventoryScreen extends StatefulWidget {
  const KeyInventoryScreen({super.key});

  @override
  State<KeyInventoryScreen> createState() => _KeyInventoryScreenState();
}

class _KeyInventoryScreenState extends State<KeyInventoryScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(LoadKeyInventory());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ResellerBloc, ResellerState>(
      builder: (context, state) {
        if (state.isLoading && state.activationKeys.isEmpty) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading key inventory...'),
          );
        }

        final availableKeys =
            state.activationKeys.where((k) => k.isAvailable).toList();
        final usedKeys = state.activationKeys.where((k) => k.isUsed).toList();

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Key Inventory'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Available'),
                  Tab(text: 'Sold/Used'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GenerateKeysScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _KeyList(
                  keys: availableKeys,
                  emptyMessage: 'No available keys',
                  emptyIcon: Icons.vpn_key,
                ),
                _KeyList(
                  keys: usedKeys,
                  emptyMessage: 'No sold keys',
                  emptyIcon: Icons.sell,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeyList extends StatelessWidget {
  final List<dynamic> keys;
  final String emptyMessage;
  final IconData emptyIcon;

  const _KeyList({
    required this.keys,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) {
      return EmptyStateWidget(
        icon: emptyIcon,
        title: emptyMessage,
        subtitle: 'Generate new keys to see them here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: key.isAvailable
                    ? AppTheme.successColor.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.vpn_key,
                color: key.isAvailable ? AppTheme.successColor : Colors.grey,
              ),
            ),
            title: Text(
              key.key,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            subtitle: Text(
              key.isAvailable
                  ? 'Available until ${_formatDate(key.expiresAt)}'
                  : 'Used on ${_formatDate(key.usedAt)}',
            ),
            trailing: key.isAvailable
                ? IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      // Share key with dealer
                    },
                  )
                : null,
          ),
        );
      },
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class GenerateKeysScreen extends StatefulWidget {
  const GenerateKeysScreen({super.key});

  @override
  State<GenerateKeysScreen> createState() => _GenerateKeysScreenState();
}

class _GenerateKeysScreenState extends State<GenerateKeysScreen> {
  int _quantity = 10;
  bool _isGenerating = false;

  Future<void> _generateKeys() async {
    setState(() => _isGenerating = true);

    try {
      context.read<ResellerBloc>().add(GenerateKeys(quantity: _quantity));
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ResellerBloc, ResellerState>(
      listener: (context, state) {
        if (state.generatedKeys.isNotEmpty) {
          _showKeysDialog(context, state.generatedKeys);
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Generate Keys'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.vpn_key,
                          size: 64,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Number of Keys',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _quantity > 1
                                  ? () => setState(() => _quantity--)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline),
                              iconSize: 32,
                            ),
                            Container(
                              width: 80,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _quantity.toString(),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium,
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _quantity++),
                              icon: const Icon(Icons.add_circle_outline),
                              iconSize: 32,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [10, 25, 50, 100].map((n) {
                            return ActionChip(
                              label: Text('$n'),
                              onPressed: () => setState(() => _quantity = n),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: state.isLoading || _isGenerating ? null : _generateKeys,
                  icon: _isGenerating || state.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate $_quantity Keys'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showKeysDialog(BuildContext context, List<dynamic> keys) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keys Generated'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: keys.length,
            itemBuilder: (context, index) {
              final key = keys[index];
              return ListTile(
                title: Text(
                  key.key,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    // Copy to clipboard
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Share all keys
            },
            icon: const Icon(Icons.share),
            label: const Text('Share All'),
          ),
        ],
      ),
    );
  }
}

class DealerDetailScreen extends StatefulWidget {
  final String dealerId;

  const DealerDetailScreen({super.key, required this.dealerId});

  @override
  State<DealerDetailScreen> createState() => _DealerDetailScreenState();
}

class _DealerDetailScreenState extends State<DealerDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ResellerBloc>().add(LoadDealerDetail(dealerId: widget.dealerId));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ResellerBloc, ResellerState>(
      builder: (context, state) {
        if (state.isLoading && state.selectedDealer == null) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading dealer details...'),
          );
        }

        final dealer = state.selectedDealer;
        if (dealer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Dealer Details')),
            body: const ErrorDisplayWidget(message: 'Dealer not found'),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(dealer.name),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: AppTheme.primaryColor,
                          child: const Icon(
                            Icons.store,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          dealer.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dealer.shopName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondaryColor,
                              ),
                        ),
                        const SizedBox(height: 8),
                        StatusBadge(status: dealer.status),
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
                          'Contact Information',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        _InfoRow(label: 'Phone', value: dealer.phone),
                        _InfoRow(label: 'Email', value: 'N/A'),
                        _InfoRow(label: 'Address', value: dealer.address),
                        _InfoRow(label: 'Trade License', value: dealer.tradeLicense),
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
                          'Business Stats',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                label: 'Total Devices',
                                value: dealer.totalDevices.toString(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatCard(
                                label: 'Active',
                                value: dealer.activeDevices.toString(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (dealer.status != 'ACTIVE')
                  ElevatedButton.icon(
                    onPressed: () {
                      _showActivateDialog(context, dealer);
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Activate Dealer'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showActivateDialog(BuildContext context, dealer) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activate Dealer'),
        content: const Text(
          'This will assign an activation key to this dealer. '
          'Make sure you have available keys in your inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Show key selection dialog then activate
            },
            child: const Text('Select Key & Activate'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondaryColor,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}