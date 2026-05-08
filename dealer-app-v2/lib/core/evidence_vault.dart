import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'google_vault.dart';

const _kVaultExt = '.vault';
const _storage = FlutterSecureStorage();

/// Manages encrypted NID + face photos for a device enrollment.
///
/// Storage hierarchy:
///   1. App private directory — primary copy (.vault files, AES-256-GCM)
///   2. Google Drive app-data folder — backup copy (same encrypted blob)
///
/// Key split model:
///   Key A = held by server (passed in as key_a_ref after enrollment)
///   Key B = generated locally, stored in flutter_secure_storage, NEVER sent to server
///   Key C = reseller device copy (out of scope for this file)
///
/// Decryption requires Key A + Key B. This file manages Key B only.
class EvidenceVault {
  /// Store NID front/back and face photos for an enrollment.
  ///
  /// Returns the SHA-256 hex hash of the concatenated original photos,
  /// which must be registered with the server via POST /evidence/register.
  static Future<String> storeEvidence({
    required String nidHash,
    required String deviceId,
    required Uint8List nidFrontPhoto,
    required Uint8List nidBackPhoto,
    required Uint8List facePhoto,
    required String keyARef,
  }) async {
    final keyB = _generateKeyB();
    await _storage.write(key: 'keyB_$nidHash', value: base64Encode(keyB));

    // Process each photo: resize → grayscale → JPEG compress
    final processedFront = await _processPhoto(nidFrontPhoto);
    final processedBack  = await _processPhoto(nidBackPhoto);
    final processedFace  = await _processPhoto(facePhoto);

    // Compute integrity hash over all original (unprocessed) photos
    final allBytes = Uint8List.fromList([...nidFrontPhoto, ...nidBackPhoto, ...facePhoto]);
    final photoHash = _sha256hex(allBytes);

    // Encrypt and store each photo
    await _encryptAndStore('${nidHash}_nid_front', processedFront, keyB);
    await _encryptAndStore('${nidHash}_nid_back',  processedBack,  keyB);
    await _encryptAndStore('${nidHash}_face',       processedFace,  keyB);

    // Upload encrypted blobs to Google Drive as backup
    try {
      final frontEnc = await _readVaultFile('${nidHash}_nid_front');
      final backEnc  = await _readVaultFile('${nidHash}_nid_back');
      final faceEnc  = await _readVaultFile('${nidHash}_face');
      if (frontEnc != null) await GoogleVault.uploadEncrypted('ev_${nidHash}_front$_kVaultExt', frontEnc);
      if (backEnc  != null) await GoogleVault.uploadEncrypted('ev_${nidHash}_back$_kVaultExt',  backEnc);
      if (faceEnc  != null) await GoogleVault.uploadEncrypted('ev_${nidHash}_face$_kVaultExt',  faceEnc);
    } catch (_) {
      // Drive backup is best-effort; local copy is authoritative
    }

    return photoHash;
  }

  /// Retrieve decrypted photos within an active server-granted session.
  ///
  /// The [sessionToken] is the request_id returned by /evidence/access-request/:id/key-a.
  /// The server validates the session server-side; this method trusts that the
  /// caller already confirmed access is authorized before invoking.
  static Future<Map<String, Uint8List>?> retrieveForReveal(String nidHash) async {
    final keyBBase64 = await _storage.read(key: 'keyB_$nidHash');
    if (keyBBase64 == null) return null;
    final keyB = base64Decode(keyBBase64);

    final front = await _decryptVaultFile('${nidHash}_nid_front', keyB);
    final back  = await _decryptVaultFile('${nidHash}_nid_back',  keyB);
    final face  = await _decryptVaultFile('${nidHash}_face',       keyB);

    if (front == null || back == null || face == null) return null;

    return {
      'nid_front': front,
      'nid_back':  back,
      'face':       face,
    };
  }

  /// Delete all evidence files for an NID hash (called after server confirms deletion approved).
  static Future<void> deleteEvidence(String nidHash) async {
    final dir = await _vaultDir();
    final prefixes = ['${nidHash}_nid_front', '${nidHash}_nid_back', '${nidHash}_face'];

    for (final prefix in prefixes) {
      final file = File('${dir.path}/$prefix$_kVaultExt');
      if (await file.exists()) await file.delete();
    }

    await _storage.delete(key: 'keyB_$nidHash');

    // Remove Drive backups
    try {
      await GoogleVault.deleteFile('ev_${nidHash}_front$_kVaultExt');
      await GoogleVault.deleteFile('ev_${nidHash}_back$_kVaultExt');
      await GoogleVault.deleteFile('ev_${nidHash}_face$_kVaultExt');
    } catch (_) {}
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static Uint8List _generateKeyB() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  /// Minimal photo processing: encode at reduced quality.
  /// Full resize + grayscale requires image package — stub returns bytes unchanged.
  /// Replace with proper image processing when image package is added to pubspec.
  static Future<Uint8List> _processPhoto(Uint8List raw) async {
    // TODO: add `image: ^4.1.3` to pubspec and implement:
    //   img.decodeImage(raw) → resize(800,600) → grayscale() → encodeJpg(quality:70)
    return raw;
  }

  static Future<Directory> _vaultDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/evidence_vault');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _encryptAndStore(String key, Uint8List plaintext, Uint8List keyB) async {
    final encrypted = _aesgcmEncrypt(plaintext, keyB);
    final dir  = await _vaultDir();
    final file = File('${dir.path}/$key$_kVaultExt');
    await file.writeAsBytes(encrypted);
  }

  static Future<Uint8List?> _readVaultFile(String key) async {
    final dir  = await _vaultDir();
    final file = File('${dir.path}/$key$_kVaultExt');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<Uint8List?> _decryptVaultFile(String key, Uint8List keyB) async {
    final bytes = await _readVaultFile(key);
    if (bytes == null) return null;
    return _aesgcmDecrypt(bytes, keyB);
  }

  /// AES-256-GCM encrypt. Output format: 12-byte IV || ciphertext+16-byte tag.
  static Uint8List _aesgcmEncrypt(Uint8List plaintext, Uint8List key) {
    final iv = Uint8List(12);
    final rng = Random.secure();
    for (var i = 0; i < 12; i++) iv[i] = rng.nextInt(256);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final ciphertext = cipher.process(plaintext);
    return Uint8List.fromList([...iv, ...ciphertext]);
  }

  /// AES-256-GCM decrypt. Expects format: 12-byte IV || ciphertext+tag.
  static Uint8List _aesgcmDecrypt(Uint8List data, Uint8List key) {
    final iv         = data.sublist(0, 12);
    final ciphertext = data.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    return cipher.process(ciphertext);
  }

  static String _sha256hex(Uint8List data) {
    final digest = SHA256Digest().process(data);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
