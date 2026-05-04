import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/services/api_client.dart';
import '../../shared/models/lock_request.dart';
import '../auth/auth_bloc.dart';

class LockRequestsScreen extends StatefulWidget {
  const LockRequestsScreen({super.key});

  @override
  State<LockRequestsScreen> createState() => _LockRequestsScreenState();
}

class _LockRequestsScreenState extends State<LockRequestsScreen> {
  final ApiClient _apiClient = ApiClient();
  List<LockRequest> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final authState = context.read<AuthBloc>().state;
      final response = await _apiClient.get(
        '/lock-requests',
        queryParameters: {'dealer_id': authState.user?.id},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['requests'] ?? [];
        _requests = data.map((json) => LockRequest.fromJson(json)).toList();
      }
    } catch (e) {
      // Handle silently
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lock Requests'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: _isLoading
            ? const LoadingIndicator(message: 'Loading requests...')
            : _requests.isEmpty
                ? const EmptyState(
                    icon: Icons.lock_outlined,
                    title: 'No Lock Requests',
                    subtitle: 'Your lock requests will appear here',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (context, index) {
                      final request = _requests[index];
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
                                  Text(
                                    'Request #${request.id.substring(0, 8)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  _StatusChip(status: request.status),
                                ],
                              ),
                              const Divider(),
                              _infoRow('Device ID', request.deviceId.substring(0, 8)),
                              _infoRow('Reason', _getReasonLabel(request.reasonCode)),
                              if (request.dealerNote != null)
                                _infoRow('Note', request.dealerNote!),
                              _infoRow(
                                'Submitted',
                                '${request.createdAt.year}-${request.createdAt.month.toString().padLeft(2, '0')}-${request.createdAt.day.toString().padLeft(2, '0')}',
                              ),
                              if (request.verificationResult != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    request.verificationResult!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _getReasonLabel(String code) {
    for (final reason in LockReason.reasons) {
      if (reason.code == code) return reason.label;
    }
    return code;
  }
}

class _StatusChip extends StatelessWidget {
  final LockRequestStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        _getLabel(),
        style: TextStyle(
          color: _getColor(),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (status) {
      case LockRequestStatus.pending:
        return AppTheme.warningColor;
      case LockRequestStatus.approved:
        return AppTheme.successColor;
      case LockRequestStatus.rejected:
        return AppTheme.errorColor;
      case LockRequestStatus.executed:
        return AppTheme.primaryColor;
    }
  }

  String _getLabel() {
    switch (status) {
      case LockRequestStatus.pending:
        return 'Pending';
      case LockRequestStatus.approved:
        return 'Approved';
      case LockRequestStatus.rejected:
        return 'Rejected';
      case LockRequestStatus.executed:
        return 'Executed';
    }
  }
}