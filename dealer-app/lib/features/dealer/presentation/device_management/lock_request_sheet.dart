import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/services/device_management_service.dart';

class LockRequestSheet extends StatefulWidget {
  final Device device;
  final Function(bool)? onResult;

  const LockRequestSheet({
    super.key,
    required this.device,
    this.onResult,
  });

  @override
  State<LockRequestSheet> createState() => _LockRequestSheetState();
}

class _LockRequestSheetState extends State<LockRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _totpController = TextEditingController();
  final _noteController = TextEditingController();
  final _deviceService = DeviceManagementService();

  String? _selectedReason;
  bool _isProcessing = false;
  bool _showResult = false;
  bool _isApproved = false;
  String _resultMessage = '';

  int get _noteLength => _noteController.text.length;

  final Map<String, String> _reasonCodes = {
    'EMI_OVERDUE_1_5': 'EMI Overdue (1-5 Days)',
    'EMI_OVERDUE_6_15': 'EMI Overdue (6-15 Days)',
    'EMI_OVERDUE_15_PLUS': 'EMI Overdue (15+ Days)',
    'CONTACT_LOST': 'Customer Unreachable',
    'FRAUD_SUSPECTED': 'Fraud Suspected',
    'TAMPER_DETECTED': 'Device Tampering Detected',
  };

  @override
  void dispose() {
    _totpController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
      _showResult = false;
    });

    try {
      final result = await _deviceService.submitLockRequest(
        deviceId: widget.device.id,
        reasonCode: _selectedReason!,
        totpCode: _totpController.text,
        dealerNote: _noteController.text.isEmpty ? null : _noteController.text,
      );

      setState(() {
        _isApproved = result.approved;
        if (result.approved) {
          _resultMessage = result.message;
        } else {
          _resultMessage =
              'Your lock request is invalid. ${result.rejectionReason ?? result.message}. The device has NOT been locked.';
        }
        _showResult = true;
        _isProcessing = false;
      });

      widget.onResult?.call(result.approved);
    } catch (e) {
      setState(() {
        _isApproved = false;
        _resultMessage = 'An error occurred while processing: $e';
        _showResult = true;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Request Lock',
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
                const SizedBox(height: 8),
                Text(
                  'IMEI: ${widget.device.imei1}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                _buildEmiStatusCard(),
                const SizedBox(height: 20),
                const Text(
                  'Reason for Lock',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedReason,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  hint: const Text('Select a reason'),
                  items: _reasonCodes.entries.map((e) {
                    return DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedReason = val),
                  validator: (val) =>
                      val == null ? 'Please select a reason' : null,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Dealer Note (Optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _noteController,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hintText: 'Add any additional details...',
                    counterText: '$_noteLength/200',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2FA Confirmation (TOTP)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _totpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.security),
                    hintText: 'Enter 6-digit code',
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Please enter the TOTP code';
                    }
                    if (val.length != 6) {
                      return 'TOTP must be 6 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (_showResult) _buildResultCard(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'SUBMIT LOCK REQUEST',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmiStatusCard() {
    final device = widget.device;
    final isPaidOff = device.isPaidOff;
    final isOverdue = device.isPaymentOverdue;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPaidOff
            ? Colors.green[50]
            : isOverdue
                ? Colors.red[50]
                : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPaidOff
              ? Colors.green
              : isOverdue
                  ? Colors.red
                  : Colors.blue,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPaidOff
                    ? Icons.verified
                    : isOverdue
                        ? Icons.warning
                        : Icons.info,
                color: isPaidOff
                    ? Colors.green
                    : isOverdue
                        ? Colors.red
                        : Colors.blue,
              ),
              const SizedBox(width: 8),
              const Text(
                'Current EMI Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('EMI Amount:'),
              Text(
                '৳${device.emiAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount:'),
              Text(
                '৳${device.totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Paid Amount:'),
              Text(
                '৳${device.paidAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Remaining:'),
              Text(
                '৳${device.remainingAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isPaidOff ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Next Payment Due:'),
              Text(
                DateFormat('yyyy-MM-dd').format(device.nextPaymentDate),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('EMI Tenure:'),
              Text(
                '${device.emiTenure} months',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (isOverdue) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment is overdue! Lock request is valid.',
                      style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isApproved ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isApproved ? Colors.green : Colors.red),
      ),
      child: Column(
        children: [
          Icon(
            _isApproved ? Icons.check_circle : Icons.cancel,
            color: _isApproved ? Colors.green : Colors.red,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            _isApproved ? 'REQUEST APPROVED' : 'REQUEST REJECTED',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: _isApproved ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _resultMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _isApproved ? Colors.green[800] : Colors.red[800],
            ),
          ),
          if (!_isApproved) ...[
            const SizedBox(height: 8),
            Text(
              'The device has NOT been locked.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red[900],
              ),
            ),
          ],
        ],
      ),
    );
  }
}