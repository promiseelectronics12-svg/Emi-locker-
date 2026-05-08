import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:dealer_app/core/evidence_vault.dart';

class EvidenceVaultScreen extends StatefulWidget {
  const EvidenceVaultScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EvidenceVaultScreen> createState() => _EvidenceVaultScreenState();
}

class _EvidenceVaultScreenState extends State<EvidenceVaultScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidence vault'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Enroll'),
            Tab(text: 'Access requests'),
            Tab(text: 'Delete'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _EnrollTab(api: widget.api),
          const _AccessRequestsTab(),
          _DeleteTab(api: widget.api),
        ],
      ),
    );
  }
}

// ── Enroll tab ────────────────────────────────────────────────────────────────

class _EnrollTab extends StatefulWidget {
  const _EnrollTab({required this.api});

  final ApiClient api;

  @override
  State<_EnrollTab> createState() => _EnrollTabState();
}

class _EnrollTabState extends State<_EnrollTab> {
  final _nidHashCtrl  = TextEditingController();
  final _deviceIdCtrl = TextEditingController();
  final _keyARefCtrl  = TextEditingController();

  // Photo slots: null = not picked
  Uint8List? _nidFront;
  Uint8List? _nidBack;
  Uint8List? _face;

  bool _busy = false;
  String _errorMsg = '';
  String? _photoHash;

  @override
  void dispose() {
    _nidHashCtrl.dispose();
    _deviceIdCtrl.dispose();
    _keyARefCtrl.dispose();
    super.dispose();
  }

  void _setFakePhoto(String slot) {
    // Placeholder: image_picker not yet available — use 1×1 white JPEG stub
    const stubJpeg = [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
      0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
      0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
      0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
      0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
      0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
      0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFB, 0x28,
      0xA2, 0x80, 0xFF, 0xD9,
    ];
    final bytes = Uint8List.fromList(stubJpeg);
    setState(() {
      if (slot == 'front') _nidFront = bytes;
      if (slot == 'back')  _nidBack  = bytes;
      if (slot == 'face')  _face     = bytes;
    });
  }

  Future<void> _enroll() async {
    final nidHash  = _nidHashCtrl.text.trim();
    final deviceId = _deviceIdCtrl.text.trim();
    final keyARef  = _keyARefCtrl.text.trim();

    if (nidHash.length != 64) {
      setState(() => _errorMsg = 'NID hash must be 64 hex characters');
      return;
    }
    if (deviceId.isEmpty) {
      setState(() => _errorMsg = 'Device ID is required');
      return;
    }
    if (_nidFront == null || _nidBack == null || _face == null) {
      setState(() => _errorMsg = 'All three photos are required');
      return;
    }
    if (keyARef.isEmpty) {
      setState(() => _errorMsg = 'Key A ref is required');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() { _busy = true; _errorMsg = ''; _photoHash = null; });

    try {
      final hash = await EvidenceVault.storeEvidence(
        nidHash: nidHash,
        deviceId: deviceId,
        nidFrontPhoto: _nidFront!,
        nidBackPhoto: _nidBack!,
        facePhoto: _face!,
        keyARef: keyARef,
      );

      await widget.api.post('/api/v1/evidence/register', data: {
        'nid_hash':   nidHash,
        'device_id':  deviceId,
        'photo_hash': hash,
        'key_a_ref':  keyARef,
      });

      if (mounted) {
        setState(() { _photoHash = hash; _busy = false; });
        snack(context, 'Evidence enrolled');
      }
    } catch (e) {
      if (mounted) {
        setState(() { _errorMsg = readableError(e); _busy = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_photoHash != null) {
      return _EnrollSuccess(
        photoHash: _photoHash!,
        onDone: () => setState(() {
          _photoHash = null;
          _nidHashCtrl.clear();
          _deviceIdCtrl.clear();
          _keyARefCtrl.clear();
          _nidFront = _nidBack = _face = null;
        }),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InlineNotice(
          message:
              'Photos are encrypted on-device before being stored or uploaded. '
              'Only you can decrypt them.',
          tone: AppTone.info,
          icon: Icons.lock_outlined,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _nidHashCtrl,
          decoration: const InputDecoration(
            labelText: 'NID hash (SHA-256)',
            prefixIcon: Icon(Icons.fingerprint_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _deviceIdCtrl,
          decoration: const InputDecoration(
            labelText: 'Device ID',
            prefixIcon: Icon(Icons.phone_android_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyARefCtrl,
          decoration: const InputDecoration(
            labelText: 'Key A ref (from enrollment)',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
        ),
        const SizedBox(height: 20),

        Text('Photos',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppTone.muted)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _PhotoSlot(
                label: 'NID Front',
                picked: _nidFront != null,
                onPick: () => _setFakePhoto('front'))),
            const SizedBox(width: 8),
            Expanded(child: _PhotoSlot(
                label: 'NID Back',
                picked: _nidBack != null,
                onPick: () => _setFakePhoto('back'))),
            const SizedBox(width: 8),
            Expanded(child: _PhotoSlot(
                label: 'Face',
                picked: _face != null,
                onPick: () => _setFakePhoto('face'))),
          ],
        ),

        if (_errorMsg.isNotEmpty) ...[
          const SizedBox(height: 16),
          InlineNotice(
              message: _errorMsg,
              tone: AppTone.danger,
              icon: Icons.error_outline),
        ],

        const SizedBox(height: 24),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock_outlined, size: 16),
          label: const Text('Encrypt & enroll'),
          onPressed: _busy ? null : _enroll,
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.label,
    required this.picked,
    required this.onPick,
  });

  final String label;
  final bool picked;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: picked
              ? AppTone.brand.withOpacity(0.06)
              : AppTone.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: picked
                ? AppTone.brand.withOpacity(0.4)
                : AppTone.muted.withOpacity(0.3),
            style: picked ? BorderStyle.solid : BorderStyle.solid,
            width: picked ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              picked ? Icons.check_circle_outline_rounded : Icons.image_outlined,
              color: picked ? AppTone.brand : AppTone.muted,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    color: picked ? AppTone.brand : AppTone.muted,
                    fontWeight:
                        picked ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _EnrollSuccess extends StatelessWidget {
  const _EnrollSuccess({required this.photoHash, required this.onDone});

  final String photoHash;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTone.brand.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outlined,
                color: AppTone.brand, size: 36),
          ),
          const SizedBox(height: 20),
          const Text('Evidence enrolled',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTone.ink)),
          const SizedBox(height: 8),
          const Text(
            'Photos encrypted and stored locally + backed up to Google Drive.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTone.muted),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTone.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTone.muted.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Photo hash',
                    style: TextStyle(
                        fontSize: 11, color: AppTone.muted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(photoHash,
                    style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                        color: AppTone.ink)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onDone, child: const Text('Enroll another')),
        ],
      ),
    );
  }
}

// ── Access requests tab ───────────────────────────────────────────────────────

class _AccessRequestsTab extends StatelessWidget {
  const _AccessRequestsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Empty('No pending access requests'),
    );
  }
}

// ── Delete tab ────────────────────────────────────────────────────────────────

class _DeleteTab extends StatefulWidget {
  const _DeleteTab({required this.api});

  final ApiClient api;

  @override
  State<_DeleteTab> createState() => _DeleteTabState();
}

class _DeleteTabState extends State<_DeleteTab> {
  final _hashCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _hashCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final nidHash = _hashCtrl.text.trim();
    if (nidHash.length != 64) {
      snack(context, 'NID hash must be 64 hex characters');
      return;
    }
    if (_confirmCtrl.text.trim() != 'DELETE') {
      snack(context, 'Type DELETE to confirm');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all evidence?'),
        content: const Text(
            'This will permanently delete all encrypted photos from this device '
            'and from Google Drive. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppTone.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.heavyImpact();
    setState(() { _busy = true; _done = false; });

    try {
      await EvidenceVault.deleteEvidence(nidHash);
      // Best-effort server notification
      try {
        await widget.api.post('/api/v1/evidence/delete-request',
            data: {'nid_hash': nidHash});
      } catch (_) {}

      if (mounted) setState(() { _busy = false; _done = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, readableError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 48, color: AppTone.muted),
              SizedBox(height: 12),
              Text('Evidence deleted',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTone.ink)),
              SizedBox(height: 6),
              Text('All photos removed from device and Google Drive.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTone.muted)),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const InlineNotice(
          message:
              'This permanently deletes all encrypted photos for this NID. '
              'This cannot be undone.',
          tone: AppTone.danger,
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _hashCtrl,
          decoration: const InputDecoration(
            labelText: 'NID hash (SHA-256)',
            prefixIcon: Icon(Icons.fingerprint_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmCtrl,
          decoration: const InputDecoration(
            labelText: 'Type DELETE to confirm',
            prefixIcon: Icon(Icons.keyboard_outlined),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_outline_rounded, size: 16),
          label: const Text('Delete evidence'),
          onPressed: _busy ? null : _delete,
          style: FilledButton.styleFrom(
            backgroundColor: AppTone.danger,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ],
    );
  }
}
