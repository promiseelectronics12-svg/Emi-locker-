import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/constants/constants.dart';
import '../../../shared/models/device_model.dart';
import '../bloc/dealer_bloc.dart';

class DealerDashboardScreen extends StatefulWidget {
  const DealerDashboardScreen({super.key});

  @override
  State<DealerDashboardScreen> createState() => _DealerDashboardScreenState();
}

class _DealerDashboardScreenState extends State<DealerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DealerBloc>().add(LoadDashboard());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DealerBloc, DealerState>(
      builder: (context, state) {
        if (state.isLoading && state.analytics == null) {
          return const Scaffold(
            body: LoadingWidget(message: 'Loading dashboard...'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            context.read<DealerBloc>().add(LoadDashboard());
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
                  'Here\'s your business overview',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondaryColor,
                      ),
                ),
                const SizedBox(height: 24),
                if (state.analytics != null) ...[
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      ProgressCard(
                        title: 'Total Devices',
                        value: state.analytics!.totalDevices.toString(),
                        icon: Icons.phone_android,
                        color: AppTheme.primaryColor,
                      ),
                      ProgressCard(
                        title: 'Active',
                        value: state.analytics!.activeDevices.toString(),
                        icon: Icons.check_circle,
                        color: AppTheme.successColor,
                      ),
                      ProgressCard(
                        title: 'Locked',
                        value: state.analytics!.lockedDevices.toString(),
                        icon: Icons.lock,
                        color: AppTheme.errorColor,
                      ),
                      ProgressCard(
                        title: 'Overdue',
                        value: state.analytics!.overdueDevices.toString(),
                        icon: Icons.warning,
                        color: AppTheme.warningColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ProgressCard(
                          title: 'Revenue',
                          value: '৳${_formatNumber(state.analytics!.totalRevenue)}',
                          icon: Icons.attach_money,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ProgressCard(
                          title: 'Pending',
                          value: '৳${_formatNumber(state.analytics!.pendingAmount)}',
                          icon: Icons.hourglass_empty,
                          color: AppTheme.warningColor,
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
                                  icon: Icons.add_circle,
                                  label: 'Enroll Device',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/dealer/enroll',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _QuickActionButton(
                                  icon: Icons.qr_code_scanner,
                                  label: 'Scan QR',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/dealer/scan',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _QuickActionButton(
                                  icon: Icons.lock,
                                  label: 'Lock Request',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    '/dealer/lock-requests',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (state.recentDevices.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Devices',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/dealer/devices',
                          ),
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...state.recentDevices.take(5).map((device) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: DeviceCard(
                            title: device.customerName,
                            subtitle: device.imei1,
                            status: device.status,
                            secondaryText:
                                '৳${_formatNumber(device.paidAmount)} / ৳${_formatNumber(device.totalAmount)}',
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/dealer/device/${device.id}',
                            ),
                          ),
                        )),
                  ],
                ],
                if (state.error != null) ...[
                  ErrorDisplayWidget(
                    message: state.error!,
                    onRetry: () => context.read<DealerBloc>().add(LoadDashboard()),
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