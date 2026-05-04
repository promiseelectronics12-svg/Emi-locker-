import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../shared/models/device_model.dart';
import '../../../shared/api/api_client.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/device_status_card.dart';
import 'device_detail_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final String? filter;

  const DeviceListScreen({super.key, this.filter});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<DeviceModel> _devices = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiClient = getIt<ApiClient>();
      final response = await apiClient.getDevices();

      if (response.statusCode == 200) {
        final List<dynamic> deviceList = response.data['devices'] ?? [];
        setState(() {
          _devices = deviceList.map((d) => DeviceModel.fromJson(d)).toList();
          _applyFilter();
        });
      } else {
        setState(() => _error = 'Failed to load devices');
      }
    } catch (e) {
      setState(() => _error = 'Network error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    if (widget.filter == null) return;

    switch (widget.filter) {
      case 'active':
        _devices = _devices.where((d) => d.status == DeviceStatus.active).toList();
        break;
      case 'overdue':
        _devices = _devices.where((d) => d.isPaymentOverdue).toList();
        break;
      case 'locked':
        _devices = _devices.where((d) => d.status == DeviceStatus.locked).toList();
        break;
    }
  }

  List<DeviceModel> get _filteredDevices {
    return _devices;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String _getTitle() {
    switch (widget.filter) {
      case 'active':
        return 'Active Devices';
      case 'overdue':
        return 'Overdue Payments';
      case 'locked':
        return 'Locked Devices';
      default:
        return 'All Devices';
    }
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
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDevices,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredDevices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_other, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No devices found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredDevices.length,
        itemBuilder: (context, index) {
          final device = _filteredDevices[index];
          return DeviceStatusCard(
            device: device,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DeviceDetailScreen(device: device),
                ),
              );
            },
          );
        },
      ),
    );
  }
}