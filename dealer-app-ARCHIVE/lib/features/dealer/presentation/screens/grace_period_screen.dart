import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

class GracePeriodScreen extends StatefulWidget {
  final String deviceId;

  const GracePeriodScreen({super.key, required this.deviceId});

  @override
  State<GracePeriodScreen> createState() => _GracePeriodScreenState();
}

class _GracePeriodScreenState extends State<GracePeriodScreen> {
  String _selectedPeriod = '3_DAYS';
  bool _isUpdating = false;

  final Map<String, int> _periodOptions = {
    '1_DAY': 1,
    '3_DAYS': 3,
    '7_DAYS': 7,
    '14_DAYS': 14,
    '30_DAYS': 30,
  };

  void _updateGracePeriod() async {
    setState(() => _isUpdating = true);

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grace period updated successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Grace Period'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Grace Period',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This determines how long the customer has to make payment before the device is automatically locked.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    ...(_periodOptions.entries.map((entry) {
                      return RadioListTile<String>(
                        title: Text('${entry.value} Day${entry.value > 1 ? 's' : ''}'),
                        subtitle: Text(_getDescription(entry.value)),
                        value: entry.key,
                        groupValue: _selectedPeriod,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedPeriod = value;
                            });
                          }
                        },
                      );
                    })),
                  ],
                ),
              ),
            ),
            const Spacer(),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'The grace period starts from the scheduled payment date.',
                        style: TextStyle(color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isUpdating ? null : _updateGracePeriod,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dealerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isUpdating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update Grace Period'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDescription(int days) {
    switch (days) {
      case 1:
        return 'Urgent - immediate action required';
      case 3:
        return 'Short extension for urgent cases';
      case 7:
        return 'Standard grace period';
      case 14:
        return 'Extended period for special circumstances';
      case 30:
        return 'Maximum allowed grace period';
      default:
        return '';
    }
  }
}