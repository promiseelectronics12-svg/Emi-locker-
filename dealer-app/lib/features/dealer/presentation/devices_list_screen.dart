import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/device.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/api_client.dart';
import '../../auth/bloc/auth_bloc.dart';

class DevicesListScreen extends StatefulWidget {
  const DevicesListScreen({super.key});

  @override
  State<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends State<DevicesListScreen> {
  final ApiClient _apiClient = ApiClient();
  List<Device> _devices = [];
  bool _isLoading = true;
  String _searchQuery = '';
  DeviceStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/dealer/devices');
      if (response.statusCode == 200) {
        final List<dynamic> devicesJson = response.data['devices'] ?? [];
        _devices = devicesJson
            .map((json) => Device.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load devices'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<Device> get _filteredDevices {
    return _devices.where((device) {
      final matchesSearch = _searchQuery.isEmpty ||
          device.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          device.imei1.contains(_searchQuery) ||
          device.customerPhone.contains(_searchQuery);

      final matchesStatus =
          _statusFilter == null || device.status == _statusFilter;

      return matchesSearch && matchesStatus;
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
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search by name, IMEI, or phone...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
            ),
          ),
          if (_statusFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Chip(
                    label: Text('Status: ${_statusFilter!.name}'),
                    onDeleted: () => setState(() => _statusFilter = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadDevices,
                    child: _filteredDevices.isEmpty
                        ? _buildEmptyState()
                        : _buildDevicesList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.phone_android,
            size: 80,
            color: AppTheme.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != null
                ? 'No devices match your filters'
                : 'No devices enrolled yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to enroll a new device',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredDevices.length,
      itemBuilder: (context, index) {
        final device = _filteredDevices[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  DeviceStatusColors.getColor(device.status.name),
              child: const Icon(Icons.phone_android, color: Colors.white),
            ),
            title: Text(device.customerName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.imei1),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '৳${device.monthlyEmi.toStringAsFixed(0)}/mo',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${device.paidMonths}/${device.tenureMonths} months',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DeviceStatusColors.getColor(device.status.name)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                device.statusDisplayName,
                style: TextStyle(
                  color: DeviceStatusColors.getColor(device.status.name),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            isThreeLine: true,
            onTap: () => Navigator.pushNamed(
              context,
              '/device-details',
              arguments: device,
            ),
          ),
        );
      },
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter by Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _statusFilter == null,
                  onSelected: (_) {
                    setState(() => _statusFilter = null);
                    Navigator.pop(context);
                  },
                ),
                ...DeviceStatus.values.map((status) {
                  return FilterChip(
                    label: Text(status.name),
                    selected: _statusFilter == status,
                    onSelected: (_) {
                      setState(() => _statusFilter = status);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
