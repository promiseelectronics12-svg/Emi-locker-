import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../shared/models/alert_model.dart';

class AlertCenterSheet extends StatelessWidget {
  final List<AlertModel> alerts;
  final Function(String) onMarkRead;
  final Function(String) onDismiss;

  const AlertCenterSheet({
    super.key,
    required this.alerts,
    required this.onMarkRead,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Alert Center',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: alerts.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final alert = alerts[index];
                          return _AlertCard(
                            alert: alert,
                            onMarkRead: () => onMarkRead(alert.id),
                            onDismiss: () => onDismiss(alert.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No alerts',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'re all caught up!',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final AlertModel alert;
  final VoidCallback onMarkRead;
  final VoidCallback onDismiss;

  const _AlertCard({
    required this.alert,
    required this.onMarkRead,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getBorderColor()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getTypeColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.type.displayName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getSeverityColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.severity.displayName.toUpperCase(),
                  style: TextStyle(
                    color: _getSeverityColor(),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM dd, HH:mm').format(alert.createdAt),
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            alert.message,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
            ),
          ),
          if (alert.metadata != null) ...[
            const SizedBox(height: 8),
            _buildMetadata(),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!alert.isRead)
                TextButton.icon(
                  onPressed: onMarkRead,
                  icon: const Icon(Icons.done, size: 16),
                  label: const Text('Mark Read'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              TextButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Dismiss'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadata() {
    final metadata = alert.metadata;
    if (metadata == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: metadata.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
                Text(
                  entry.value.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getTypeColor() {
    switch (alert.type) {
      case AlertType.fraudAlert:
        return Colors.red;
      case AlertType.anomalyDetection:
        return Colors.orange;
      case AlertType.adminMessage:
        return Colors.blue;
      case AlertType.paymentReminder:
        return Colors.green;
      case AlertType.lockStatusChange:
        return Colors.purple;
    }
  }

  Color _getSeverityColor() {
    switch (alert.severity) {
      case AlertSeverity.low:
        return Colors.green;
      case AlertSeverity.medium:
        return Colors.orange;
      case AlertSeverity.high:
        return Colors.red;
      case AlertSeverity.critical:
        return Colors.deepPurple;
    }
  }

  Color _getBackgroundColor() {
    switch (alert.severity) {
      case AlertSeverity.low:
        return Colors.green[50]!;
      case AlertSeverity.medium:
        return Colors.orange[50]!;
      case AlertSeverity.high:
        return Colors.red[50]!;
      case AlertSeverity.critical:
        return Colors.purple[50]!;
    }
  }

  Color _getBorderColor() {
    switch (alert.severity) {
      case AlertSeverity.low:
        return Colors.green[200]!;
      case AlertSeverity.medium:
        return Colors.orange[200]!;
      case AlertSeverity.high:
        return Colors.red[200]!;
      case AlertSeverity.critical:
        return Colors.purple[200]!;
    }
  }
}