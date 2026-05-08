import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Offline-first local vault.
///
/// Stores a dealer's device list and key inventory in flutter_secure_storage
/// (backed by Android Keystore / iOS Keychain — encrypted at the OS level).
/// No additional encryption package is needed.
///
/// Usage:
///   - Call [LocalVault.syncDevices] / [LocalVault.syncKeys] after every
///     successful API load to keep the vault current.
///   - Call [LocalVault.read] when the server is unreachable to display
///     cached data.
///   - Call [LocalVault.clear] on logout.
class LocalVault {
  LocalVault._();

  static const _storage = FlutterSecureStorage();

  static const _metaKey = 'vault_meta';
  static const _devicePrefix = 'vault_device_';
  static const _keyPrefix = 'vault_key_';

  // ── Write ────────────────────────────────────────────────────────────────

  /// Persists the dealer's device list. Safe to call on every page load.
  static Future<void> syncDevices(
    String dealerId,
    List<Map<String, dynamic>> devices,
  ) async {
    final deviceIds = <String>[];
    for (final d in devices) {
      final id = d['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await _storage.write(
        key: '$_devicePrefix$id',
        value: jsonEncode(d),
      );
      deviceIds.add(id);
    }
    await _updateMeta(dealerId, deviceIds: deviceIds);
  }

  /// Persists the dealer's key inventory. Safe to call on every page load.
  static Future<void> syncKeys(
    String dealerId,
    List<Map<String, dynamic>> keys,
  ) async {
    final keyIds = <String>[];
    for (final k in keys) {
      final id = k['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await _storage.write(
        key: '$_keyPrefix$id',
        value: jsonEncode(k),
      );
      keyIds.add(id);
    }
    await _updateMeta(dealerId, keyIds: keyIds);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Returns the last synced vault snapshot, or null if nothing is cached.
  static Future<VaultSnapshot?> read() async {
    final rawMeta = await _storage.read(key: _metaKey);
    if (rawMeta == null) return null;

    final meta = jsonDecode(rawMeta) as Map<String, dynamic>;
    final dealerId = meta['dealer_id'] as String? ?? '';
    final syncedAt = meta['synced_at'] as String?;
    final deviceIds = List<String>.from(meta['device_ids'] as List? ?? []);
    final keyIds = List<String>.from(meta['key_ids'] as List? ?? []);

    final devices = <Map<String, dynamic>>[];
    for (final id in deviceIds) {
      final raw = await _storage.read(key: '$_devicePrefix$id');
      if (raw != null) {
        devices.add(jsonDecode(raw) as Map<String, dynamic>);
      }
    }

    final keys = <Map<String, dynamic>>[];
    for (final id in keyIds) {
      final raw = await _storage.read(key: '$_keyPrefix$id');
      if (raw != null) {
        keys.add(jsonDecode(raw) as Map<String, dynamic>);
      }
    }

    if (devices.isEmpty && keys.isEmpty) return null;

    return VaultSnapshot(
      dealerId: dealerId,
      syncedAt: syncedAt != null ? DateTime.tryParse(syncedAt) : null,
      devices: devices,
      keys: keys,
    );
  }

  // ── Export ────────────────────────────────────────────────────────────────

  /// Returns a JSON string of the full vault (for share/export).
  /// The data is already OS-encrypted at rest; this export is plaintext JSON
  /// intended for the dealer's own backup use.
  static Future<String?> exportJson() async {
    final snapshot = await read();
    if (snapshot == null) return null;
    return jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'dealer_id': snapshot.dealerId,
      'synced_at': snapshot.syncedAt?.toIso8601String(),
      'device_count': snapshot.devices.length,
      'key_count': snapshot.keys.length,
      'devices': snapshot.devices,
      'keys': snapshot.keys,
    });
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  /// Removes all vault data. Call on logout.
  static Future<void> clear() async {
    final rawMeta = await _storage.read(key: _metaKey);
    if (rawMeta != null) {
      final meta = jsonDecode(rawMeta) as Map<String, dynamic>;
      for (final id in List<String>.from(meta['device_ids'] as List? ?? [])) {
        await _storage.delete(key: '$_devicePrefix$id');
      }
      for (final id in List<String>.from(meta['key_ids'] as List? ?? [])) {
        await _storage.delete(key: '$_keyPrefix$id');
      }
    }
    await _storage.delete(key: _metaKey);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  static Future<void> _updateMeta(
    String dealerId, {
    List<String>? deviceIds,
    List<String>? keyIds,
  }) async {
    final rawMeta = await _storage.read(key: _metaKey);
    final existing = rawMeta != null
        ? jsonDecode(rawMeta) as Map<String, dynamic>
        : <String, dynamic>{};

    final updated = {
      'dealer_id': dealerId,
      'synced_at': DateTime.now().toIso8601String(),
      'device_ids': deviceIds ?? List<String>.from(existing['device_ids'] as List? ?? []),
      'key_ids': keyIds ?? List<String>.from(existing['key_ids'] as List? ?? []),
    };

    await _storage.write(key: _metaKey, value: jsonEncode(updated));
  }
}

class VaultSnapshot {
  const VaultSnapshot({
    required this.dealerId,
    required this.devices,
    required this.keys,
    this.syncedAt,
  });

  final String dealerId;
  final DateTime? syncedAt;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> keys;

  bool get isEmpty => devices.isEmpty && keys.isEmpty;
}
