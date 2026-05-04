import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device/device_model.dart';
import '../../services/device/device_service.dart';

class LockRequestSheet extends StatefulWidget {
  final DeviceModel device;
  const LockRequestSheet({super.key, required this.device});

  @override
  State<<LockLockRequestSheet> createState() => _LockRequestSheetState();
}

class _LockRequestSheetState extends State<<LockLockRequestSheet> {
  final _formKey = GlobalKey<<FormFormState>();
  final _noteController = TextEditingController();
  String? _selectedReason;
  String _totp = '';
  bool _isSubmitting = false;
  String? _resultStatus; // 'approved', 'rejected'
  String? _resultMessage;

  final List<<<MapMap<<StringString, String>> _reasons = [
    {'code': 'EMI_OVERDUE_1_5', 'label': 'EMI Overdue (1-5 Days)'},
    {'code': 'EMI_OVERDUE_6_15', 'label': 'EMI Overdue (6-15 Days)'},
    {'code': 'EMI_OVERDUE_15+', 'label': 'EMI Overdue (15+ Days)'},
    {'code': 'CONTACT_LOST', 'label': 'Customer Unreachable'},
  ];

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _resultStatus = null;
    });

    try {
      final service = DeviceService();
      final success = await service.requestLock(
        widget.device.id,
        _selectedReason!,
        _noteController.text,
        _totp,
      );

      setState(() {
        if (success) {
          _resultStatus = 'approved';
          _resultMessage = 'Lock request APPROVED. Device is being locked.';
        } else {
          _resultStatus = 'rejected';
          _resultMessage = 'Your lock request is invalid. Server verification failed. The device has NOT been locked.';
        }
      });
    } catch (e) {
      setState(() {
        _resultStatus = 'rejected';
        _resultMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request Lock: ${widget.device.imei}', 
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            _buildEMISummary(),
            const SizedBox(height: 20),
            
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reason for Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButtonFormField<<StringString>(
                    value: _selectedReason,
                    items: _reasons.map((r) => DropdownMenuItem(
                      value: r['code'],
                      child: Text(r['label']!),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedReason = val),
                    validator: (val) => val == null ? 'Please select a reason' : null,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextFormField(
                    controller: _noteController,
                    maxLength: 200,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text('2FA Confirmation (TOTP)', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextFormField(
                    onChanged: (val) => _totp = val,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter 6-digit code',
                    ),
                    validator: (val) => (val == null || val.length <<  6) ? 'Enter valid TOTP' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            if (_resultStatus == 'approved') _buildResultCard(Colors.green, _resultMessage!),
            if (_resultStatus == 'rejected') _buildResultCard(Colors.red, _resultMessage!),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text('SUBMIT LOCK REQUEST'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEMISummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current EMI Status', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Last Payment: 2026-04-01'),
          Text('Next Due: 2026-05-01'),
          Text('Overdue Amount: 4,500 BDT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildResultCard(Color color, String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(message, style: TextStyle(color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    );
  }
}
