import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../shared/models/device_model.dart';

class GracePeriodDialog extends StatefulWidget {
  final Device device;
  final Future<bool> Function(int days, String totp) onSubmit;

  const GracePeriodDialog({
    super.key,
    required this.device,
    required this.onSubmit,
  });

  @override
  State<GracePeriodDialog> createState() => _GracePeriodDialogState();
}

class _GracePeriodDialogState extends State<GracePeriodDialog> {
  final _formKey = GlobalKey<FormState>();
  final _totpController = TextEditingController();

  int _selectedDays = 3;
  bool _isProcessing = false;

  final List<int> _dayOptions = [1, 3, 5, 7, 14, 30];

  @override
  void dispose() {
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    final success = await widget.onSubmit(_selectedDays, _totpController.text);

    if (mounted) {
      Navigator.pop(context, success ? _selectedDays : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Grant Grace Period'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device: ${widget.device.imei1}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Grace Period Duration',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dayOptions.map((days) {
                final isSelected = _selectedDays == days;
                return ChoiceChip(
                  label: Text('$days days'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedDays = days);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              '2FA Confirmation (TOTP)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _totpController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter 6-digit code',
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please enter TOTP';
                }
                if (val.length != 6) {
                  return 'TOTP must be 6 digits';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _submit,
          child: _isProcessing
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Grant'),
        ),
      ],
    );
  }
}