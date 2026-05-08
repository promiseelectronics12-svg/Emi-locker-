import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/models/device.dart';
import '../bloc/device_bloc.dart';
import '../bloc/device_event.dart';
import '../bloc/device_state.dart';

import '../../../shared/models/lock_request.dart';

class LockRequestSheet extends StatefulWidget {
  final Device device;

  const LockRequestSheet({super.key, required this.device});

  @override
  State<LockRequestSheet> createState() => _LockRequestSheetState();
}

class _LockRequestSheetState extends State<LockRequestSheet> {
  final _noteController = TextEditingController();
  final _totpController = TextEditingController();
  String? _selectedReason;
  final _formKey = GlobalKey<FormState>();

  late List<LockReason> _availableReasons;

  @override
  void initState() {
    super.initState();
    _calculateAvailableReasons();
  }

  void _calculateAvailableReasons() {
    final overdueDays = DateTime.now().difference(widget.device.nextPaymentDate).inDays;
    _availableReasons = LockReason.predefinedReasons.where((r) {
      return overdueDays >= r.minOverdueDays;
    }).toList();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeviceBloc, DeviceState>(
      listener: (context, state) {
        if (state.lockRequestResult != null && state.isLockRequestApproved == true) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      builder: (context, state) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
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
                const Text(
                  'Request Device Lock',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildEmiStatusCard(),
                const SizedBox(height: 24),
                if (state.lockRequestResult == null) ...[
                  const Text('Reason for Lock', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildReasonDropdown(),
                  const SizedBox(height: 16),
                  _buildNoteField(),
                  const SizedBox(height: 16),
                  const Text('2FA Confirmation', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildTotpField(),
                  const SizedBox(height: 24),
                  _buildSubmitButton(context, state),
                ] else
                  _buildResultCard(state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmiStatusCard() {
    final overdueDays = DateTime.now().difference(widget.device.nextPaymentDate).inDays;
    final isOverdue = overdueDays > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOverdue ? AppTheme.errorColor.withOpacity(0.1) : AppTheme.successColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? AppTheme.errorColor.withOpacity(0.3) : AppTheme.successColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOverdue ? Icons.error_outline : Icons.check_circle_outline,
            color: isOverdue ? AppTheme.errorColor : AppTheme.successColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverdue ? 'EMI OVERDUE' : 'PAYMENT UP TO DATE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isOverdue ? AppTheme.errorColor : AppTheme.successColor,
                  ),
                ),
                Text(
                  isOverdue 
                    ? '$overdueDays days past due date (${DateFormat('MMM dd').format(widget.device.nextPaymentDate)})'
                    : 'Next payment due: ${DateFormat('MMM dd').format(widget.device.nextPaymentDate)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonDropdown() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        hintText: 'Select a valid reason',
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _selectedReason,
      items: _availableReasons.map((r) {
        return DropdownMenuItem(
          value: r.code,
          child: Text(r.label),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedReason = val),
      validator: (val) => val == null ? 'Please select a reason' : null,
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      maxLength: 200,
      maxLines: 2,
      decoration: const InputDecoration(
        labelText: 'Optional Note',
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _buildTotpField() {
    return TextFormField(
      controller: _totpController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(letterSpacing: 8, fontSize: 18, fontWeight: FontWeight.bold),
      decoration: const InputDecoration(
        hintText: '000000',
        counterText: '',
      ),
      validator: (val) => (val?.length ?? 0) < 6 ? 'Enter 6-digit TOTP' : null,
    );
  }

  Widget _buildSubmitButton(BuildContext context, DeviceState state) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: state.isSubmittingLock ? null : () => _submit(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.errorColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: state.isSubmittingLock
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('SUBMIT LOCK REQUEST'),
      ),
    );
  }

  Widget _buildResultCard(DeviceState state) {
    final bool approved = state.isLockRequestApproved ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: approved ? AppTheme.successColor : AppTheme.errorColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            approved ? Icons.verified_user : Icons.gpp_bad,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            approved ? 'REQUEST APPROVED' : 'REQUEST REJECTED',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            approved 
              ? 'The device has been successfully locked.' 
              : 'Your lock request is invalid. ${state.lockRequestResult}. The device has NOT been locked.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          if (approved) ...[
            const SizedBox(height: 16),
            const Text(
              'Closing in 2 seconds...',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.read<DeviceBloc>().add(LoadDevices()), // Or just reset result
              child: const Text('TRY AGAIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  void _submit(BuildContext context) {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<DeviceBloc>().add(RequestLock(
        deviceId: widget.device.id,
        reasonCode: _selectedReason!,
        note: _noteController.text,
        totpCode: _totpController.text,
      ));
    }
  }
}
