import 'package:flutter/material.dart';
import '../../models/device_management/device_model.dart';
import '../../services/device_management/device_service.dart';

class LockRequestSheet extends StatefulWidget {
  final Device device;

  const LockRequestSheet({super.key, required this.device});

  @override
  State<<<<LockLockRequestSheet> LockRequestSheetState get createState() => LockRequestSheetState();
}

class LockRequestSheetState extends State<<<<LockLockRequestSheet> {
  final DeviceService _service = DeviceService();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _totpController = TextEditingController();
  String? _selectedReason;
  bool _isLoading = false;
  LockRequestResult? _result;

  final Map<<<StringStringString, String> _reasonCodes = {
    'LATE_PAYMENT': 'Payment Overdue (1-5 Days)',
    'CRITICAL_OVERDUE': 'Critical Overdue (> 5 Days)',
    'FRAUD_SUSPECTED': 'Suspected Fraud/Theft',
    'CONTRACT_BREACH': 'Contractual Violation',
  };

  void _submitRequest() async {
    if (_selectedReason == null || _totpController.text.length <<  6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please provide reason and valid TOTP')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await _service.submitLockRequest(
        deviceId: widget.device.id,
        reasonCode: _selectedReason!,
        note: _noteController.text,
      );
      setState(() {
        _result = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lock Request: ${widget.device.imei}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            
            // EMI Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CURRENT EMI STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('Overdue: ${widget.device.overdueDays} Days | Next: ${widget.device.nextPaymentAmount} BDT (${widget.device.nextPaymentDate})'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text('Reason for Lock'),
            DropdownButton<<StringString>(
              isExpanded: true,
              value: _selectedReason,
              items: _reasonCodes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (val) => setState(() => _selectedReason = val),
            ),

            const SizedBox(height: 16),
            const Text('Notes (Optional)'),
            TextField(
              controller: _noteController,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Enter reasons or evidence...'),
            ),

            const SizedBox(height: 16),
            const Text('2FA Verification (TOTP)'),
            TextField(
              controller: _totpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Enter 6-digit code'),
            ),

            const SizedBox(height: 24),
            if (_result == null)
              SizedBox(
                width: double.infinity,
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(onPressed: _submitRequest, child: const Text('Submit Lock Request')),
              )
            else
              _buildResultCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _result!.success ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _result!.success ? Colors.green : Colors.red),
      ),
      child: Column(
        children: [
          Text(_result!.success ? 'APPROVED' : 'REJECTED', 
            style: TextStyle(fontWeight: FontWeight.bold, color: _result!.success ? Colors.green.shade900 : Colors.red.shade900)),
          const SizedBox(height: 8),
          Text(_result!.message, textAlign: TextAlign.center),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
