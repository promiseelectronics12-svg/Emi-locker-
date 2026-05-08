import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dealer_app/app/emi_locker_app.dart';

class DeviceSearchScreen extends StatefulWidget {
  const DeviceSearchScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<DeviceSearchScreen> createState() => _DeviceSearchScreenState();
}

class _DeviceSearchScreenState extends State<DeviceSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  bool _searching = false;
  List<Map<String, dynamic>> _results = [];
  String _query = '';
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final q = _controller.text.trim();
    if (q == _query) return;
    _query = q;

    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() { _results = []; _searching = false; _errorMsg = ''; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() { _searching = true; _errorMsg = ''; });
    try {
      final res = await widget.api.get(
          '/api/v1/dealer/devices/search', query: {'q': q});
      final data = asMap(res.data);
      final list = (data['devices'] as List? ?? [])
          .map((e) => asMap(e))
          .toList();
      if (mounted) setState(() { _results = list; _searching = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _errorMsg = readableError(e); _searching = false; });
      }
    }
  }

  void _openDevice(BuildContext ctx, Map<String, dynamic> device) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DeviceActions(
        api: widget.api,
        device: device,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          decoration: InputDecoration(
            hintText: 'Search by name, IMEI, brand or model…',
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      _focus.requestFocus();
                    },
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 48, color: AppTone.muted),
            SizedBox(height: 12),
            Text(
              'Search by name, IMEI,\nbrand or model',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTone.muted, fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            SkeletonBox(width: double.infinity, height: 60),
            SizedBox(height: 8),
            SkeletonBox(width: double.infinity, height: 60),
            SizedBox(height: 8),
            SkeletonBox(width: double.infinity, height: 60),
          ],
        ),
      );
    }

    if (_errorMsg.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: InlineNotice(
              message: _errorMsg,
              tone: AppTone.danger,
              icon: Icons.error_outline),
        ),
      );
    }

    if (_results.isEmpty) {
      return Empty('No devices match "$_query"');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (ctx, i) {
        final d = _results[i];
        final name  = text(d['device_name'] ?? d['model'], fallback: 'Device');
        final imei  = text(d['imei']);
        final brand = text(d['brand']);
        final status = text(d['status'], fallback: 'unknown');

        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          tileColor: AppTone.surface,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTone.muted.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.phone_android_outlined,
                size: 20, color: AppTone.muted),
          ),
          title: Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
            [if (brand.isNotEmpty) brand, if (imei.isNotEmpty) imei].join(' · '),
            style: const TextStyle(fontSize: 11, color: AppTone.muted),
          ),
          trailing: StatusPill(label: status, color: statusColor(status)),
          onTap: () => _openDevice(ctx, d),
        );
      },
    );
  }
}
