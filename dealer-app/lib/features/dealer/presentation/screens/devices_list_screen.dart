import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/services/api_client.dart';
import '../../../../shared/models/device_model.dart';
import '../../../../shared/repositories/device_repository.dart';

class DevicesListScreen extends StatefulWidget {
  const DevicesListScreen({super.key});

  @override
  State<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends State<DevicesListScreen> {
  final DeviceRepository _repository = DeviceRepository();
  List<Device> _devices = [];
  bool _isLoading = true;
  String _filterStatus = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final devices = await _repository.getDevices('dealer_123');
      setState(() {
        _devices = devices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Device> get _filteredDevices {
    var filtered = _devices;

    if (_filterStatus != 'ALL') {
      filtered = filtered.where((d) => d.status == _filterStatus).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) {
        return d.customerName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            d.customerPhone.contains(_searchQuery) ||
            d.id.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        backgroundColor: AppTheme.dealerColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: _DeviceSearchDelegate(_filteredDevices),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _filterStatus = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'ALL', child: Text('All')),
              const PopupMenuItem(value: 'ACTIVE', child: Text('Active')),
              const PopupMenuItem(value: 'LOCKED', child: Text('Locked')),
              const PopupMenuItem(value: 'OVERDUE', child: Text('Overdue')),
              const PopupMenuItem(value: 'DECOUPLED', child: Text('Decoupled')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredDevices.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _filteredDevices.length,
                    itemBuilder: (context, index) {
                      final device = _filteredDevices[index];
                      return _DeviceCard(
                        device: device,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/dealer/device-detail',
                            arguments: device,
                          );
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pushNamed(context, '/dealer/enroll');
        },
        backgroundColor: AppTheme.dealerColor,
        icon: const Icon(Icons.add),
        label: const Text('Enroll'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phone_android, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 24),
          const Text(
            'No Devices Found',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _filterStatus == 'ALL'
                ? 'Start by enrolling your first device'
                : 'No $_filterStatus devices found',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback onTap;

  const _DeviceCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getStatusColor(device.status),
                    child: Icon(
                      _getStatusIcon(device.status),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.customerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          device.customerPhone,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(device.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      device.status,
                      style: TextStyle(
                        color: _getStatusColor(device.status),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoItem(
                    label: 'IMEI',
                    value: device.imei1.substring(device.imei1.length - 6),
                  ),
                  if (device.emiAmount != null)
                    _InfoItem(
                      label: 'EMI',
                      value: '৳${device.emiAmount!.toStringAsFixed(0)}',
                    ),
                  if (device.nextPaymentDate != null)
                    _InfoItem(
                      label: 'Next Pay',
                      value: _formatDate(device.nextPaymentDate!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return AppTheme.successColor;
      case 'LOCKED':
        return AppTheme.errorColor;
      case 'OVERDUE':
        return AppTheme.warningColor;
      case 'DECOUPLED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return Icons.check_circle;
      case 'LOCKED':
        return Icons.lock;
      case 'OVERDUE':
        return Icons.warning;
      case 'DECOUPLED':
        return Icons.link_off;
      default:
        return Icons.help;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _DeviceSearchDelegate extends SearchDelegate<Device?> {
  final List<Device> devices;

  _DeviceSearchDelegate(this.devices);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    final results = devices.where((d) {
      return d.customerName.toLowerCase().contains(query.toLowerCase()) ||
          d.customerPhone.contains(query) ||
          d.imei1.contains(query);
    }).toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final device = results[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(device.customerName[0]),
          ),
          title: Text(device.customerName),
          subtitle: Text(device.customerPhone),
          onTap: () {
            close(context, device);
          },
        );
      },
    );
  }
}