import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../shared/models/device_model.dart';

class MessageDialog extends StatefulWidget {
  final Device device;
  final Future<bool> Function(String message, String totp) onSubmit;

  const MessageDialog({
    super.key,
    required this.device,
    required this.onSubmit,
  });

  @override
  State<MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<MessageDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _totpController = TextEditingController();

  bool _isProcessing = false;

  @override
  void dispose() {
    _messageController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    final success = await widget.onSubmit(
      _messageController.text,
      _totpController.text,
    );

    if (mounted) {
      Navigator.pop(context, success ? _messageController.text : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Message'),
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
            Text(
              'Customer: ${widget.device.customerName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            const Text(
              'Message',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              maxLength: 160,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter message to send to device...',
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please enter a message';
                }
                return null;
              },
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
              : const Text('Send'),
        ),
      ],
    );
  }
}