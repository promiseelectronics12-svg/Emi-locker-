import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/device_model.dart';

class LockRequestScreen extends StatefulWidget {
  final DeviceModel device;

  const LockRequestScreen({super.key, required this.device});

  @override
  State<LockRequestScreen> createState() => _LockRequestScreenState();
}

class _LockRequestScreenState extends State<LockRequestScreen> {
  final _noteController = TextEditingController();
  String? _selectedReason;
  bool _loading = false;
  final _localAuth = LocalAuthentication();

  static const Map<String, String> _lockReasons = {
    'missed_payment': 'Missed EMI Payment',
    'fraud_detected': 'Fraud Detected',
    'stolen_device': 'Device Reported Stolen',
    'violation_of_terms': 'Violation of EMI Terms',
    'customer_request': 'Customer Request',
  };

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Lock')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    _row('IMEI', widget.device.imei),
                    _row('Owner', widget.device.ownerName ?? '-'),
                    _row(
                      'EMI Remaining',
                      '${widget.device.emiRemaining ?? 0} months',
                    ),
                    _row('Status', widget.device.status.toUpperCase()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Lock Reason', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedReason,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.report_problem),
              ),
              hint: const Text('Select a reason'),
              items: _lockReasons.entries.map((e) {
                return DropdownMenuItem(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: (val) => setState(() => _selectedReason = val),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Additional Note (optional)',
                prefixIcon: Icon(Icons.note),
                hintText: 'Max 200 characters',
              ),
              maxLength: 200,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            const Card(
              color: Color(0xFFFFF3E0),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Lock requests are verified by the server against EMI data. Invalid requests will be rejected.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submitLockRequest,
                icon: const Icon(Icons.lock),
                label: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Lock Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Future<void> _submitLockRequest() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a lock reason')),
      );
      return;
    }

    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      if (canAuth) {
        final didAuth = await _localAuth.authenticate(
          localizedReason: 'Confirm lock request with biometric',
          options: const AuthenticationOptions(biometricOnly: true),
        );
        if (!didAuth) return;
      }
    } catch (_) {}

    setState(() => _loading = true);
    try {
      await Injection.apiClient.post(
        '/api/v1/devices/${widget.device.id}/lock-request',
        data: {
          'reason_code': _selectedReason,
          'dealer_note': _noteController.text.isEmpty
              ? null
              : _noteController.text,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lock request submitted. Awaiting server verification.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }
}
