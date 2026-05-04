import 'package:flutter/material.dart';
import '../../../../shared/api/api_client.dart';
import '../../../../shared/repositories/reseller_repository.dart';
import '../../../../shared/models/key_request.dart';
import '../../../../shared/models/reseller_stats.dart';
import '../../../../shared/theme/app_theme.dart';

class KeyRequestScreen extends StatefulWidget {
  const KeyRequestScreen({super.key});

  @override
  State<KeyRequestScreen> createState() => _KeyRequestScreenState();
}

class _KeyRequestScreenState extends State<KeyRequestScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient();
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSubmitting = false;

  int _monthlyQuota = 0;
  int _keysUsedThisMonth = 0;
  int _availableKeys = 0;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _approvedRequests = [];
  List<Map<String, dynamic>> _rejectedRequests = [];

  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _justificationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quantityController.dispose();
    _justificationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/reseller/key-requests');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _monthlyQuota = data['monthly_quota'] ?? 0;
          _keysUsedThisMonth = data['keys_used_this_month'] ?? 0;
          _availableKeys = data['available_keys'] ?? 0;
          _pendingRequests =
              List<Map<String, dynamic>>.from(data['pending_requests'] ?? []);
          _approvedRequests =
              List<Map<String, dynamic>>.from(data['approved_requests'] ?? []);
          _rejectedRequests =
              List<Map<String, dynamic>>.from(data['rejected_requests'] ?? []);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  int get _maxRequestQuantity {
    final twentyPercent = (_monthlyQuota * 0.20).floor();
    final remainingQuota = _monthlyQuota - _keysUsedThisMonth;
    return remainingQuota < twentyPercent ? remainingQuota : twentyPercent;
  }

  String? _validateQuantity(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a quantity';
    }
    final qty = int.tryParse(value);
    if (qty == null || qty <= 0) {
      return 'Please enter a valid quantity';
    }
    if (qty > _maxRequestQuantity) {
      return 'Maximum allowed: $_maxRequestQuantity (20% of monthly quota)';
    }
    return null;
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final quantity = int.parse(_quantityController.text);
    final justification = _justificationController.text.trim();

    final confirm = await showConfirmDialog(
      context,
      title: 'Confirm Request',
      message: 'Request $quantity keys?\n\nJustification: $justification',
      confirmText: 'Submit Request',
    );

    if (!confirm) return;

    setState(() => _isSubmitting = true);

    try {
      final response = await _apiClient.post('/reseller/key-requests', data: {
        'quantity': quantity,
        'justification': justification,
      });

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request submitted successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
          _quantityController.clear();
          _justificationController.clear();
          _loadData();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.data['message'] ?? 'Request failed'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Keys'),
        backgroundColor: AppTheme.resellerColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'New Request'),
            Tab(text: 'Request History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNewRequestTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  Widget _buildNewRequestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildQuotaInfoCard(),
            const SizedBox(height: 16),
            _buildRequestFormCard(),
            const SizedBox(height: 16),
            _buildRequestLimitWarning(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaInfoCard() {
    final remainingQuota = _monthlyQuota - _keysUsedThisMonth;
    final progress = _monthlyQuota > 0 ? _keysUsedThisMonth / _monthlyQuota : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Quota',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_keysUsedThisMonth / $_monthlyQuota',
                    style: const TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: AppTheme.dividerColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 0.8 ? AppTheme.warningColor : AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$remainingQuota keys remaining',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                Text(
                  'Max per request: $_maxRequestQuantity',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildQuickStat('Available', '$_availableKeys', AppTheme.successColor),
                ),
                Expanded(
                  child: _buildQuickStat('Used This Month', '$_keysUsedThisMonth', AppTheme.primaryColor),
                ),
                Expanded(
                  child: _buildQuickStat('Total Quota', '$_monthlyQuota', AppTheme.accentColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRequestFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Key Request',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              validator: _validateQuantity,
              decoration: InputDecoration(
                labelText: 'Number of Keys',
                hintText: 'Enter quantity (max: $_maxRequestQuantity)',
                prefixIcon: const Icon(Icons.vpn_key),
                suffixText: 'keys',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _justificationController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Justification',
                hintText: 'Explain why you need these keys...',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please provide a justification';
                }
                if (value.trim().length < 10) {
                  return 'Justification must be at least 10 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.resellerColor,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestLimitWarning() {
    return Card(
      color: AppTheme.warningColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.warningColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Request Limit',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.warningColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Single requests cannot exceed 20% of your monthly quota ( $_maxRequestQuantity keys). '
                    'Multiple requests can be made until quota is reached.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.warningColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    final allRequests = [
      ..._pendingRequests.map((r) => {...r, 'status': 'pending'}),
      ..._approvedRequests.map((r) => {...r, 'status': 'approved'}),
      ..._rejectedRequests.map((r) => {...r, 'status': 'rejected'}),
    ];

    allRequests.sort((a, b) {
      final aDate = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
      final bDate = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
      return bDate.compareTo(aDate);
    });

    if (allRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 80,
              color: AppTheme.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No requests yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your key requests will appear here',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allRequests.length,
        itemBuilder: (context, index) {
          final request = allRequests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] as String;
    final quantity = request['quantity'] ?? 0;
    final justification = request['justification'] ?? '';
    final createdAt = DateTime.tryParse(request['created_at'] ?? '');
    final adminNote = request['admin_note'] as String?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = AppTheme.successColor;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = AppTheme.errorColor;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = AppTheme.warningColor;
        statusIcon = Icons.pending;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.vpn_key, color: AppTheme.primaryColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '$quantity keys',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              justification,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            if (adminNote != null && adminNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.dividerColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.comment, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        adminNote,
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              createdAt != null ? _formatDateTime(createdAt) : '',
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}