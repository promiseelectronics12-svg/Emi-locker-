import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/models/lock_request_model.dart';

class SubmitLockRequestScreen extends StatefulWidget {
  final String deviceId;
  final String customerName;
  final String customerPhone;
  final String currentStatus;

  const SubmitLockRequestScreen({
    super.key,
    required this.deviceId,
    required this.customerName,
    required this.customerPhone,
    required this.currentStatus,
  });

  @override
  State<SubmitLockRequestScreen> createState() => _SubmitLockRequestScreenState();
}

class _SubmitLockRequestScreenState extends State<SubmitLockRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  final _localAuth = LocalAuthentication();

  String? _selectedReason;
  bool _isSubmitting = false;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canAuthenticate = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      setState(() {
        _canUseBiometrics = canAuthenticate;
      });
    } catch (e) {
      setState(() {
        _canUseBiometrics = false;
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    bool authenticated = false;
    if (_canUseBiometrics) {
      try {
        authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to submit lock request',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } catch (e) {
        authenticated = false;
      }
    } else {
      authenticated = true;
    }

    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lock request submitted successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Lock'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
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
                        'Device Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Device ID', value: widget.deviceId),
                      _InfoRow(label: 'Customer', value: widget.customerName),
                      _InfoRow(label: 'Phone', value: widget.customerPhone),
                      _InfoRow(label: 'Status', value: widget.currentStatus),
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
                      const Text(
                        'EMI Status',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(label: 'Next Payment', value: '15 Jun 2026'),
                      _InfoRow(label: 'Amount Due', value: '৳5,000'),
                      _InfoRow(label: 'Days Overdue', value: '5 days'),
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
                      const Text(
                        'Lock Reason',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedReason,
                        decoration: const InputDecoration(
                          labelText: 'Select Reason',
                          prefixIcon: Icon(Icons.warning_outlined),
                        ),
                        items: LockReason.reasons.entries.map((entry) {
                          return DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedReason = value;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a lock reason';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteController,
                        maxLength: 200,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Additional Note (Optional)',
                          hintText: 'Add any additional context...',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.orange.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Lock requests are verified by the server against EMI schedule data. Invalid requests will be rejected.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Lock Request'),
              ),
            ],
          ),
        ),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class LockRequestDetailScreen extends StatelessWidget {
  final String requestId;

  const LockRequestDetailScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lock Request Details'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: const Center(
        child: Text('Request details will be displayed here'),
      ),
    );
  }
}