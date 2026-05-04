import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class MessageScreen extends StatefulWidget {
  final String deviceId;
  final String customerName;

  const MessageScreen({
    super.key,
    required this.deviceId,
    required this.customerName,
  });

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final _messageController = TextEditingController();
  String _selectedTemplate = 'DEFAULT';
  bool _isSending = false;

  final Map<String, String> _templates = {
    'DEFAULT': 'Dear Customer, please clear your outstanding EMI payment to avoid device lock.',
    'REMINDER': 'Reminder: Your EMI payment is due soon. Please ensure timely payment.',
    'WARNING': 'Warning: Your device will be locked if payment is not received.',
    'OVERDUE': 'Urgent: Your EMI is overdue. Please contact us immediately to avoid device lock.',
  };

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    setState(() => _isSending = true);

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message sent successfully'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Message'),
        backgroundColor: AppTheme.dealerColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
                      'Recipient',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.customerName,
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      'Device: ${widget.deviceId.substring(0, 8)}...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
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
                      'Message Template',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _templates.keys.map((key) {
                        final isSelected = _selectedTemplate == key;
                        return ChoiceChip(
                          label: Text(key),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedTemplate = key;
                                _messageController.text = _templates[key]!;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 5,
              maxLength: 160,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Enter your message...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Max 160 characters. Standard SMS rates apply.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendMessage,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dealerColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'Sending...' : 'Send Message'),
            ),
          ],
        ),
      ),
    );
  }
}