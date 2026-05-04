import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/models/emi_schedule_model.dart';
import '../../../shared/models/payment_model.dart';
import '../../../shared/models/gps_location_model.dart';
import '../../../shared/services/device_management_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../widgets/lock_request_sheet.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({super.key, required this.deviceId});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late DeviceManagementService _deviceService;
  DeviceModel? _device;
  List<EmiScheduleModel> _emiSchedule = [];
  List<PaymentModel> _paymentHistory = [];
  GpsLocationModel? _lastLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _deviceService = context.read<DeviceManagementService>();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _deviceService.getDeviceDetails(widget.deviceId),
        _deviceService.getEmiSchedule(widget.deviceId),
        _deviceService.getPaymentHistory(widget.deviceId),
        _deviceService.getLastKnownLocation(widget.deviceId),
      ]);

      if (mounted) {
        setState(() {
          _device = results[0] as DeviceModel;
          _emiSchedule = results[1] as List<EmiScheduleModel>;
          _paymentHistory = results[2] as List<PaymentModel>;
          _lastLocation = results[3] as GpsLocationModel?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading device details: $e')),
        );
      }
    }
  }

  Future<void> _openMap() async {
    if (_lastLocation == null) return;
    final url = 'https://www.google.com/maps/search/?api=1&query=${_lastLocation!.latitude},${_lastLocation!.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Details')),
        body: const Center(child: Text('Device not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_device!.model ?? 'Device Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(),
            const SizedBox(height: 20),
            _buildActionButtonRow(),
            const SizedBox(height: 24),
            _buildSectionTitle('Customer Information'),
            _buildCustomerInfo(),
            const SizedBox(height: 24),
            _buildSectionTitle('Device Information'),
            _buildDeviceInfo(),
            const SizedBox(height: 24),
            _buildSectionTitle('Last Known Location'),
            _buildLocationCard(),
            const SizedBox(height: 24),
            _buildSectionTitle('EMI Schedule'),
            _buildEmiSchedule(),
            const SizedBox(height: 24),
            _buildSectionTitle('Payment History'),
            _buildPaymentHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Status', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                Text(
                  _device!.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(_device!.status),
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (_device!.lockedAt != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Last State Change', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, yyyy HH:mm').format(_device!.lockedAt!),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtonRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildActionButton(
            label: 'Lock',
            icon: Icons.lock,
            color: Colors.red,
            onPressed: () => _showLockRequest(),
          ),
          _buildActionButton(
            label: 'Unlock',
            icon: Icons.lock_open,
            color: Colors.green,
            onPressed: () => _showUnlockRequest(),
          ),
          _buildActionButton(
            label: 'Grace',
            icon: Icons.update,
            color: Colors.orange,
            onPressed: () => _showGracePeriodDialog(),
          ),
          _buildActionButton(
            label: 'Message',
            icon: Icons.message,
            color: Colors.blue,
            onPressed: () => _showMessageDialog(),
          ),
          _buildActionButton(
            label: 'Pull GPS',
            icon: Icons.gps_fixed,
            color: Colors.purple,
            onPressed: () => _pullLocation(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCustomerInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow(Icons.person, 'Name', _device!.customerName),
            const Divider(),
            _buildInfoRow(Icons.phone, 'Phone', _device!.customerPhone),
            const Divider(),
            _buildInfoRow(Icons.badge, 'NID', _device!.customerNid),
            const SizedBox(height: 12),
            if (_device!.nidPhotoUrl != null)
              GestureDetector(
                onTap: () => _showNidPhoto(),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(_device!.nidPhotoUrl!),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.zoom_in, color: Colors.white, size: 32),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow(Icons.info_outline, 'Model', '${_device!.oem} ${_device!.model}'),
            const Divider(),
            _buildInfoRow(Icons.fingerprint, 'IMEI 1', _device!.imei1),
            const Divider(),
            _buildInfoRow(Icons.adb, 'Android Version', _device!.androidVersion ?? 'N/A'),
            const Divider(),
            _buildInfoRow(Icons.calendar_today, 'Enrollment Date', DateFormat('MMM d, yyyy').format(_device!.enrollmentDate)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    if (_lastLocation == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('No location data available')),
        ),
      );
    }

    return Card(
      child: InkWell(
        onTap: _openMap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastLocation!.address ?? 'Tap to view on map',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last updated: ${DateFormat('MMM d, h:mm a').format(_lastLocation!.timestamp)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmiSchedule() {
    if (_emiSchedule.isEmpty) return const Center(child: Text('No schedule available'));

    return Column(
      children: _emiSchedule.map((emi) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: emi.isPaid ? Colors.green[100] : Colors.orange[100],
              child: Text(emi.month.toString(), style: TextStyle(color: emi.isPaid ? Colors.green : Colors.orange)),
            ),
            title: Text('Installment ${emi.month}/${emi.year}'),
            subtitle: Text('Due: ${DateFormat('MMM d, yyyy').format(emi.dueDate)}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('৳${emi.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  emi.isPaid ? 'PAID' : 'UNPAID',
                  style: TextStyle(
                    fontSize: 10,
                    color: emi.isPaid ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentHistory() {
    if (_paymentHistory.isEmpty) return const Center(child: Text('No payments recorded'));

    return Column(
      children: _paymentHistory.map((payment) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.receipt_long, color: Colors.green),
            title: Text('৳${payment.amount.toStringAsFixed(0)}'),
            subtitle: Text(DateFormat('MMM d, yyyy').format(payment.paymentDate)),
            trailing: Text(payment.method ?? 'CASH', style: const TextStyle(fontSize: 12)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active: return Colors.green;
      case DeviceStatus.reminder: return Colors.blue;
      case DeviceStatus.partialLock: return Colors.orange;
      case DeviceStatus.fullLock: return Colors.red;
      case DeviceStatus.paidOff: return Colors.teal;
      case DeviceStatus.compromised: return Colors.black;
    }
  }

  void _showLockRequest() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => LockRequestSheet(device: _device!),
    );
  }

  void _showUnlockRequest() {
    // Similar to LockRequestSheet but for unlock
    _show2FADialog(
      title: 'Request Unlock',
      onConfirmed: (code) async {
        final result = await _deviceService.submitUnlockRequest(
          deviceId: _device!.id,
          totpCode: code,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message)),
          );
          _loadData();
        }
      },
    );
  }

  void _showGracePeriodDialog() {
    int selectedDays = 3;
    _show2FADialog(
      title: 'Grant Grace Period',
      extraContent: (setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select duration (days):'),
          DropdownButton<int>(
            value: selectedDays,
            items: [1, 3, 5, 7].map((d) => DropdownMenuItem(value: d, child: Text('$d Days'))).toList(),
            onChanged: (val) => setState(() => selectedDays = val!),
          ),
        ],
      ),
      onConfirmed: (code) async {
        final success = await _deviceService.grantGracePeriod(
          deviceId: _device!.id,
          days: selectedDays,
          totpCode: code,
        );
        if (mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Grace period granted')),
          );
          _loadData();
        }
      },
    );
  }

  void _showMessageDialog() {
    final controller = TextEditingController();
    _show2FADialog(
      title: 'Send Message',
      extraContent: (setState) => TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Message (max 160 chars)'),
        maxLength: 160,
      ),
      onConfirmed: (code) async {
        if (controller.text.isEmpty) return;
        await _deviceService.sendMessageToDevice(
          deviceId: _device!.id,
          message: controller.text,
          totpCode: code,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message sent')),
          );
        }
      },
    );
  }

  void _pullLocation() {
    _show2FADialog(
      title: 'Pull Location',
      onConfirmed: (code) async {
        await _deviceService.pullDeviceLocation(
          deviceId: _device!.id,
          totpCode: code,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location pull command sent')),
          );
        }
      },
    );
  }

  void _show2FADialog({
    required String title,
    Widget Function(StateSetter)? extraContent,
    required Function(String) onConfirmed,
  }) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (extraContent != null) ...[
                extraContent(setState),
                const SizedBox(height: 16),
              ],
              const Text('Enter 2FA TOTP Code from your Authenticator app:'),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(hintText: '000000'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (codeController.text.length == 6) {
                  Navigator.pop(context);
                  onConfirmed(codeController.text);
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNidPhoto() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(_device!.nidPhotoUrl!),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
