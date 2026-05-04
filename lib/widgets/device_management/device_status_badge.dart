import 'package:flutter/material.dart';

class DeviceStatusBadge extends StatelessWidget {
  final String status;

  const DeviceStatusBadge({super.key, required this.status});

  Color _getColor() {
    switch (status) {
      case 'Active': return Colors.green;
      case 'Reminder': return Colors.orange;
      case 'Partial Lock': return Colors.amber;
      case 'Full Lock': return Colors.red;
      case 'Paid Off': return Colors.blue;
      case 'Compromised': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getColor()),
      ),
      child: Text(
        status,
        style: TextStyle(color: _getColor(), fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
