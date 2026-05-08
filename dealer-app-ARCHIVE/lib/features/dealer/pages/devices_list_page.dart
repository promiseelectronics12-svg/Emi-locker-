import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/models/device.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/firebase_service.dart';
import '../bloc/auth_bloc.dart';
import 'device_detail_page.dart';

class DevicesListPage extends StatefulWidget {
  const DevicesListPage({super.key});

  @override
  State<DevicesListPage> createState() => _DevicesListPageState();
}

class _DevicesListPageState extends State<DevicesListPage> {
  final ApiClient _apiClient = ApiClient();
  final FirebaseService _firebaseService = FirebaseService();

  List<Device> _devices = [];
  bool _isLoading = true;
  String? _error;
  DeviceStatus? _filterStatus;
  String _searchQuery = '';

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
      final response = await _apiClient.get('/devices', queryParameters: {
        if (_filterStatus != null) 'status': _filterStatus.toString().split('.').last,
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['devices'] as List<dynamic>;
        setState(() {
          _devices = data
              .map((json) => Device.fromJson(json as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load devices';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Device> get _filteredDevices {
    if (_searchQuery.isEmpty) return _devices;

    final query = _searchQuery.toLowerCase();
    return _devices.where((device) {
      return device.customerName.toLowerCase().contains(query) ||
          device.customerPhone.contains(query) ||
          device.imei1.contains(query) ||
          (device.imei2?.contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or IMEI...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          if (_filterStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Chip(
                    label: Text(
                      'Filter: ${_filterStatus.toString().split('.').last}',
                    ),
                    onDeleted: () {
                      setState(() => _filterStatus = null);
                      _loadDevices();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadDevices,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadDevices,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredDevices.isEmpty
                          ? const Center(
                              child: Text('No devices found'),
                            )
                          : ListView.builder(
                              itemCount: _filteredDevices.length,
                              itemBuilder: (context, index) {
                                final device = _filteredDevices[index];
                                return _buildDeviceListItem(device);
                              },
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/enroll-device');
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDeviceListItem(Device device) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(device.status),
          radius: 24,
          child: Text(
            device.customerName.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Text(
          device.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.customerPhone,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(device.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    device.status.toString().split('.').last,
                    style: TextStyle(
                      fontSize: 10,
                      color: _getStatusColor(device.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${device.paymentProgress.toStringAsFixed(0)}% paid',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeviceDetailPage(device: device),
            ),
          );
        },
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All'),
              leading: Radio<DeviceStatus?>(
                value: null,
                groupValue: _filterStatus,
                onChanged: (value) {
                  setState(() => _filterStatus = value);
                  Navigator.pop(context);
                  _loadDevices();
                },
              ),
            ),
            ...DeviceStatus.values.map((status) {
              return ListTile(
                title: Text(status.toString().split('.').last),
                leading: Radio<DeviceStatus?>(
                  value: status,
                  groupValue: _filterStatus,
                  onChanged: (value) {
                    setState(() => _filterStatus = value);
                    Navigator.pop(context);
                    _loadDevices();
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return AppTheme.successColor;
      case DeviceStatus.locked:
        return AppTheme.errorColor;
      case DeviceStatus.gracePeriod:
        return AppTheme.warningColor;
      case DeviceStatus.pendingDecouple:
        return Colors.orange;
      case DeviceStatus.decoupled:
        return Colors.grey;
    }
  }
}