import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TotpConfirmationDialog extends StatefulWidget {
  final String action;
  final String Function(String totp) onSubmit;

  const TotpConfirmationDialog({
    super.key,
    required this.action,
    required this.onSubmit,
  });

  @override
  State<TotpConfirmationDialog> createState() => _TotpConfirmationDialogState();
}

class _TotpConfirmationDialogState extends State<TotpConfirmationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _totpController = TextEditingController();

  bool _isProcessing = false;

  @override
  void dispose() {
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    final result = widget.onSubmit(_totpController.text);

    if (mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.action),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action requires 2FA verification.',
              style: TextStyle(color: Colors.grey),
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
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.security),
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
              : const Text('Confirm'),
        ),
      ],
    );
  }
}