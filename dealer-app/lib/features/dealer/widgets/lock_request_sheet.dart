import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/services/device_management_service.dart';
import '../../../shared/theme/app_theme.dart';

class LockRequestSheet extends StatefulWidget {
  final DeviceModel device;

  const LockRequestSheet({super.key, required this.device});

  @override
  State<LockRequestSheet> createState() => _LockRequestSheetState();
}

class _LockRequestSheetState extends State<LockRequestSheet> {
  final _noteController = TextEditingController();
  final _totpController = TextEditingController();
  String _selectedReason = 'missed_payment';
  bool _isSubmitting = false;
  LockRequestResult? _result;

  final List<Map<String, String>> _allReasons = [
    {'code': 'missed_payment', 'label': 'Missed Payment', 'min_overdue': '1'},
    {'code': 'fraudulent_activity', 'label': 'Fraudulent Activity', 'min_overdue': '0'},
    {'code': 'stolen', 'label': 'Stolen Device', 'min_overdue': '0'},
    {'code': 'terms_violation', 'label': 'Terms Violation', 'min_overdue': '0'},
  ];

  @override
  void dispose() {
    _noteController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _validReasons {
    final overdueDays = widget.device.overdueDays;
    return _allReasons.where((r) {
      final min = int.parse(r['min_overdue']!);
      return overdueDays >= min;
    }).toList();
  }

  Future<void> _submitRequest() async {
    if (_totpController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit TOTP code')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _result = null;
    });

    try {
      final deviceService = context.read<DeviceManagementService>();
      final result = await deviceService.submitLockRequest(
        deviceId: widget.device.id,
        reasonCode: _selectedReason,
        totpCode: _totpController.text,
        dealerNote: _noteController.text.trim(),
      );

      setState(() {
        _result = result;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Request Device Lock',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            _buildEmiStatusCard(),
            const SizedBox(height: 20),
            if (_result == null) ...[
              _buildReasonDropdown(),
              const SizedBox(height: 16),
              _buildNoteField(),
              const SizedBox(height: 16),
              _build2FAField(),
              const SizedBox(height: 24),
              _buildSubmitButton(),
            ] else
              _buildResultCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmiStatusCard() {
    final isOverdue = widget.device.isPaymentOverdue;
    return Card(
      color: isOverdue ? Colors.red[50] : Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('EMI Status', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  isOverdue ? 'OVERDUE' : 'ON TRACK',
                  style: TextStyle(
                    color: isOverdue ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Overdue Days'),
                Text('${widget.device.overdueDays} days', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Remaining Amount'),
                Text('৳${widget.device.remainingAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonDropdown() {
    final reasons = _validReasons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Reason for Lock', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedReason,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: reasons.map((r) => DropdownMenuItem(
            value: r['code'],
            child: Text(r['label']!),
          )).toList(),
          onChanged: (val) => setState(() => _selectedReason = val!),
        ),
      ],
    );
  }

  Widget _buildNoteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Additional Note', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('${_noteController.text.length}/200', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLength: 200,
          maxLines: 2,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            counterText: '',
            hintText: 'Enter any additional details...',
          ),
          onChanged: (val) => setState(() {}),
        ),
      ],
    );
  }

  Widget _build2FAField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('2FA Confirmation', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _totpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '000000',
            counterText: '',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Enter code from your Authenticator app',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.errorColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isSubmitting
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('SUBMIT LOCK REQUEST', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildResultCard() {
    final isApproved = _result!.approved;
    return Column(
      children: [
        Card(
          color: isApproved ? Colors.green[50] : Colors.red[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isApproved ? Colors.green : Colors.red),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  isApproved ? Icons.check_circle : Icons.error,
                  color: isApproved ? Colors.green : Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  isApproved ? 'APPROVED' : 'REJECTED',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isApproved ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _result!.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                if (!isApproved && _result!.rejectionReason != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Your lock request is invalid. ${_result!.rejectionReason}. The device has NOT been locked.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ),
      ],
    );
  }
}
