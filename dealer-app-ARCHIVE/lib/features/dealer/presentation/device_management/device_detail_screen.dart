import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../../shared/models/device_model.dart';
import '../../../../shared/models/emi_schedule_model.dart';
import '../../../../shared/models/payment_model.dart';
import '../../../../shared/models/gps_location_model.dart';
import '../../../../shared/services/device_management_service.dart';
import 'lock_request_sheet.dart';
import 'widgets/grace_period_dialog.dart';
import 'widgets/message_dialog.dart';
import 'widgets/totp_confirmation_dialog.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Device device;
  final String dealerId;

  const DeviceDetailScreen({
    super.key,
    required this.device,
    required this.dealerId,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final DeviceManagementService _deviceService = DeviceManagementService();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  late Device _device;
  List<EMIScheduleModel> _emiSchedule = [];
  List<PaymentModel> _paymentHistory = [];
  GpsLocationModel? _lastLocation;
  bool _isLoading = true;
  String? _error;

  StreamSubscription<DatabaseEvent>? _deviceSubscription;

  @override
  void initState() {
    super.initState();
    _device = widget.device;
    _loadDeviceData();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _deviceSubscription?.cancel();
    super.dispose();
  }

  void _setupRealtimeListener() {
    _deviceSubscription = _dbRef
        .child('devices')
        .child(_device.id)
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          _device = Device.fromJson(data);
        });
      }
    }, onError: (error) {
      debugPrint('Device detail stream error: $error');
    });
  }

  Future<void> _loadDeviceData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _deviceService.getEmiSchedule(_device.id),
        _deviceService.getPaymentHistory(_device.id),
        _deviceService.getLastKnownLocation(_device.id),
      ]);

      setState(() {
        _emiSchedule = results[0] as List<EMIScheduleModel>;
        _paymentHistory = results[1] as List<PaymentModel>;
        _lastLocation = results[2] as GpsLocationModel?;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openMaps() async {
    if (_lastLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location data available')),
      );
      return;
    }

    final url = Uri.parse(_lastLocation!.googleMapsUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps')),
        );
      }
    }
  }

  Future<void> _openNidPhoto() async {
    final nidPhotoUrl = _device.nidPhotoUrl;
    if (nidPhotoUrl == null || nidPhotoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NID photo not available')),
      );
      return;
    }

    final url = Uri.parse(nidPhotoUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open image')),
        );
      }
    }
  }

  void _showLockRequestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LockRequestSheet(
        device: _device,
        onResult: (approved) {
          if (approved) {
            _loadDeviceData();
          }
        },
      ),
    );
  }

  void _requestUnlock() async {
    final totp = await _showTotpDialog();
    if (totp == null) return;

    try {
      final result = await _deviceService.submitUnlockRequest(
        deviceId: _device.id,
        totpCode: totp,
        reason: 'Dealer unlock request',
      );

      if (mounted) {
        _showResultSnackBar(
          result.approved,
          result.approved
              ? 'Unlock request submitted successfully'
              : 'Unlock request rejected: ${result.rejectionReason ?? result.message}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _requestGracePeriod() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => GracePeriodDialog(
        device: _device,
        onSubmit: (days, totp) async {
          try {
            await _deviceService.grantGracePeriod(
              deviceId: _device.id,
              days: days,
              totpCode: totp,
            );
            return true;
          } catch (e) {
            return false;
          }
        },
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grace period of $result days granted')),
      );
      _loadDeviceData();
    }
  }

  void _sendMessage() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => MessageDialog(
        device: _device,
        onSubmit: (message, totp) async {
          try {
            await _deviceService.sendMessageToDevice(
              deviceId: _device.id,
              message: message,
              totpCode: totp,
            );
            return true;
          } catch (e) {
            return false;
          }
        },
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent to device')),
      );
    }
  }

  void _pullLocation() async {
    final totp = await _showTotpDialog();
    if (totp == null) return;

    try {
      await _deviceService.pullDeviceLocation(
        deviceId: _device.id,
        totpCode: totp,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location pull request sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<String?> _showTotpDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => TotpConfirmationDialog(
        action: 'Confirm Action',
        onSubmit: (totp) => totp,
      ),
    );
  }

  void _showResultSnackBar(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Device ${_device.imei1}'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeviceData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load device data',
              style: TextStyle(color: Colors.red[700], fontSize: 18),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadDeviceData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDeviceData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceInfoCard(),
            const SizedBox(height: 20),
            _buildStatusSection(),
            const SizedBox(height: 20),
            _buildLocationSection(),
            const SizedBox(height: 20),
            _buildEmiSection(),
            const SizedBox(height: 20),
            _buildPaymentSection(),
            const SizedBox(height: 20),
            _buildCustomerSection(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _infoRow('IMEI 1', _device.imei1),
            if (_device.imei2.isNotEmpty) _infoRow('IMEI 2', _device.imei2),
            if (_device.macAddress != null)
              _infoRow('MAC Address', _device.macAddress!),
            if (_device.oem != null) _infoRow('OEM', _device.oem!),
            if (_device.model != null) _infoRow('Model', _device.model!),
            if (_device.androidVersion != null)
              _infoRow('Android Version', _device.androidVersion!),
            _infoRow(
              'Enrollment Date',
              DateFormat('yyyy-MM-dd').format(_device.enrollmentDate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current State',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getStatusColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _getStatusColor()),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getStatusIcon(),
                    color: _getStatusColor(),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _getStatusLabel().toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Last State Change:', style: TextStyle(color: Colors.grey)),
                  Text(
                    _device.lockedAt != null
                        ? DateFormat('yyyy-MM-dd HH:mm').format(_device.lockedAt!)
                        : 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (_device.lockedReason != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Lock Reason:', style: TextStyle(color: Colors.grey)),
                    Flexible(
                      child: Text(
                        _device.lockedReason!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Last Known Location',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ListTile(
          tileColor: Colors.grey[100],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.location_on, color: Colors.red, size: 32),
          title: _lastLocation != null
              ? Text(
                  '${_lastLocation!.latitude.toStringAsFixed(6)}, ${_lastLocation!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )
              : const Text(
                  'Location unavailable',
                  style: TextStyle(color: Colors.grey),
                ),
          subtitle: _lastLocation != null
              ? Text(
                  'Updated: ${DateFormat('yyyy-MM-dd HH:mm').format(_lastLocation!.timestamp)}',
                  style: const TextStyle(fontSize: 12),
                )
              : const Text('No location data recorded'),
          trailing: TextButton.icon(
            onPressed: _lastLocation != null ? _openMaps : null,
            icon: const Icon(Icons.map),
            label: const Text('Maps'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'EMI Schedule',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_emiSchedule.where((e) => e.isPaid).length}/${_emiSchedule.length} Paid',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_emiSchedule.isEmpty)
          _buildEmptyState('No EMI schedule available')
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _emiSchedule.length,
            itemBuilder: (context, index) {
              final emi = _emiSchedule[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: emi.isPaid ? Colors.green[50] : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: emi.isPaid ? Colors.green[200]! : Colors.grey[300]!,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emi.isPaid ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${emi.monthNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Month ${emi.monthNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Due: ${DateFormat('yyyy-MM-dd').format(emi.dueDate)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '৳${emi.amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Icon(
                          emi.isPaid ? Icons.check_circle : Icons.circle_outlined,
                          color: emi.isPaid ? Colors.green : Colors.red,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment History',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_paymentHistory.isEmpty)
          _buildEmptyState('No payment history')
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _paymentHistory.length,
            itemBuilder: (context, index) {
              final payment = _paymentHistory[index];
              return ListTile(
                tileColor: Colors.green[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                leading: CircleAvatar(
                  backgroundColor: Colors.green[100],
                  child: Icon(Icons.payments, color: Colors.green[700]),
                ),
                title: Text(
                  '৳${payment.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  payment.paymentMethod ?? 'Cash',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('MMM dd').format(payment.paidAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      payment.transactionRef ?? '',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildCustomerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Info',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _infoRow('Name', _device.customerName),
                _infoRow('NID', _device.customerNid),
                _infoRow('Phone', _device.customerPhone),
                _infoRow(
                  'Date of Birth',
                  DateFormat('yyyy-MM-dd').format(_device.customerDob),
                ),
                const SizedBox(height: 12),
                if (_device.nidPhotoUrl != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openNidPhoto,
                      icon: const Icon(Icons.image),
                      label: const Text('View NID Photo'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey[500]),
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _actionButton(
                'Request Lock',
                Icons.lock,
                Colors.red,
                _showLockRequestSheet,
              ),
              _actionButton(
                'Unlock',
                Icons.lock_open,
                Colors.green,
                _requestUnlock,
              ),
              _actionButton(
                'Grace Period',
                Icons.timer,
                Colors.orange,
                _requestGracePeriod,
              ),
              _actionButton(
                'Message',
                Icons.message,
                Colors.blue,
                _sendMessage,
              ),
              _actionButton(
                'Pull Location',
                Icons.my_location,
                Colors.purple,
                _pullLocation,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 16),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  String _getStatusLabel() {
    switch (_device.status) {
      case DeviceStatus.active:
        return 'Active';
      case DeviceStatus.reminder:
        return 'Reminder';
      case DeviceStatus.partialLock:
        return 'Partial Lock';
      case DeviceStatus.fullLock:
        return 'Full Lock';
      case DeviceStatus.paidOff:
        return 'Paid Off';
      case DeviceStatus.compromised:
        return 'Compromised';
    }
  }

  Color _getStatusColor() {
    switch (_device.status) {
      case DeviceStatus.active:
        return Colors.green;
      case DeviceStatus.reminder:
        return Colors.blue;
      case DeviceStatus.partialLock:
        return Colors.orange;
      case DeviceStatus.fullLock:
        return Colors.red;
      case DeviceStatus.paidOff:
        return Colors.grey;
      case DeviceStatus.compromised:
        return Colors.purple;
    }
  }

  IconData _getStatusIcon() {
    switch (_device.status) {
      case DeviceStatus.active:
        return Icons.check_circle;
      case DeviceStatus.reminder:
        return Icons.notifications;
      case DeviceStatus.partialLock:
        return Icons.lock;
      case DeviceStatus.fullLock:
        return Icons.lock;
      case DeviceStatus.paidOff:
        return Icons.verified;
      case DeviceStatus.compromised:
        return Icons.warning;
    }
  }
}