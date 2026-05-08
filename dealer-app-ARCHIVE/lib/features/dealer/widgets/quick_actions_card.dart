import 'package:flutter/material.dart';

class QuickActionsCard extends StatelessWidget {
  final VoidCallback? onEnrollDevice;
  final VoidCallback? onViewDevices;
  final VoidCallback? onExportNeir;
  final VoidCallback? onViewAnalytics;

  const QuickActionsCard({
    super.key,
    this.onEnrollDevice,
    this.onViewDevices,
    this.onExportNeir,
    this.onViewAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionItem(
                  context,
                  icon: Icons.add_circle,
                  label: 'Enroll',
                  onTap: onEnrollDevice,
                ),
                _buildActionItem(
                  context,
                  icon: Icons.devices,
                  label: 'Devices',
                  onTap: onViewDevices,
                ),
                _buildActionItem(
                  context,
                  icon: Icons.file_download,
                  label: 'NEIR',
                  onTap: onExportNeir,
                ),
                _buildActionItem(
                  context,
                  icon: Icons.analytics,
                  label: 'Analytics',
                  onTap: onViewAnalytics,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}