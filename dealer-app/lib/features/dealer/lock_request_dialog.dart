import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../shared/api/api_client.dart';

class LockRequestDialog extends StatefulWidget {
  final String deviceId;
  final String imei;

  const LockRequestDialog({super.key, required this.deviceId, required this.imei});

  @override
  State<LockRequestDialog> createState() => _LockRequestDialogState();
}

class _LockRequestDialogState extends State<LockRequestDialog> {
  String _selectedReason = 'NON_PAYMENT';
  final _noteController = TextEditingController();
  bool _isLoading = false;

  final List<Map<String, String>> _reasons = [
    {'code': 'NON_PAYMENT', 'label': 'EMI Non-Payment'},
    {'code': 'FRAUD_SUSPECTED', 'label': 'Suspected Fraud'},
    {'code': 'DEVICE_THEFT', 'label': 'Reported Stolen'},
    {'code': 'CONTRACT_BREACH', 'label': 'Contract Breach'},
  ];

  Future<void> _submitRequest() async {
    setState(() => _isLoading = true);
    try {
      final dio = ApiClient().dio;
      await dio.post('/devices/lock-request', data: {
        'deviceId': widget.deviceId,
        'reason': _selectedReason,
        'note': _noteController.text,
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lock request submitted. Pending server verification.')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data['message'] ?? 'Failed to submit request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Request Lock: ${widget.imei}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The server will verify the EMI schedule before approving this lock.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedReason,
              decoration: const InputDecoration(labelText: 'Reason for Lock'),
              items: _reasons.map((r) => DropdownMenuItem(
                value: r['code'],
                child: Text(r['label']!),
              )).toList(),
              onChanged: (val) => setState(() => _selectedReason = val!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (Optional)',
                hintText: 'Max 200 characters',
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRequest,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('SUBMIT REQUEST'),
        ),
      ],
    );
  }
}
