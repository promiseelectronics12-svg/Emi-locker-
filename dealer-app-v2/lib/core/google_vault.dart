import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

const _kBoundAccountKey = 'google_vault_account_email';
const _kAppDataFolderName = 'appDataFolder';

/// Authenticates http.Client using the Google Sign-In credential token.
class _AuthClient extends http.BaseClient {
  _AuthClient(this._inner, this._headers);
  final http.Client _inner;
  final Map<String, String> _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class GoogleVault {
  static final _storage = const FlutterSecureStorage();

  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  /// Returns an authenticated Drive API client, or null if not signed in.
  static Future<drive.DriveApi?> _driveApi() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) return null;

    final auth = await account.authentication;
    final client = _AuthClient(
      http.Client(),
      {'Authorization': 'Bearer ${auth.accessToken}'},
    );
    return drive.DriveApi(client);
  }

  /// One-time OAuth binding flow. Returns true if binding succeeded.
  static Future<bool> bind() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      await _storage.write(key: _kBoundAccountKey, value: account.email);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True if a Google account is bound.
  static Future<bool> isBound() async {
    final email = await _storage.read(key: _kBoundAccountKey);
    return email != null && email.isNotEmpty;
  }

  /// The email of the bound account, or null.
  static Future<String?> boundEmail() => _storage.read(key: _kBoundAccountKey);

  /// Upload an encrypted blob to the hidden app-data folder in Google Drive.
  /// The file is NOT visible in the user's regular Drive UI.
  static Future<void> uploadEncrypted(String filename, Uint8List encryptedData) async {
    final api = await _driveApi();
    if (api == null) throw Exception('Google account not signed in');

    final media = drive.Media(
      Stream.value(encryptedData),
      encryptedData.length,
      contentType: 'application/octet-stream',
    );

    // Check if file exists and update, otherwise create
    final existing = await _findFile(api, filename);
    if (existing != null) {
      await api.files.update(drive.File(), existing, uploadMedia: media);
    } else {
      final file = drive.File()
        ..name = filename
        ..parents = [_kAppDataFolderName];
      await api.files.create(file, uploadMedia: media);
    }
  }

  /// Download an encrypted blob from the app-data folder.
  static Future<Uint8List?> downloadEncrypted(String filename) async {
    final api = await _driveApi();
    if (api == null) return null;

    final fileId = await _findFile(api, filename);
    if (fileId == null) return null;

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final chunks = <int>[];
    await for (final chunk in response.stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  /// List all backup filenames in the app-data folder.
  static Future<List<String>> listFiles() async {
    final api = await _driveApi();
    if (api == null) return [];

    final result = await api.files.list(
      spaces: _kAppDataFolderName,
      $fields: 'files(id, name)',
    );
    return result.files?.map((f) => f.name ?? '').where((n) => n.isNotEmpty).toList() ?? [];
  }

  /// Delete a specific file from the app-data folder.
  static Future<void> deleteFile(String filename) async {
    final api = await _driveApi();
    if (api == null) return;

    final fileId = await _findFile(api, filename);
    if (fileId != null) {
      await api.files.delete(fileId);
    }
  }

  /// Upload a full JSON vault snapshot (devices + keys) as a single backup file.
  static Future<void> syncVaultBackup(Map<String, dynamic> snapshot) async {
    final json = jsonEncode(snapshot);
    final bytes = Uint8List.fromList(utf8.encode(json));
    await uploadEncrypted('vault_backup.json.enc', bytes);
  }

  /// Restore vault snapshot from Drive after phone loss or reinstall.
  static Future<Map<String, dynamic>?> restoreFromDrive() async {
    final bytes = await downloadEncrypted('vault_backup.json.enc');
    if (bytes == null) return null;

    final json = utf8.decode(bytes);
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<String?> _findFile(drive.DriveApi api, String filename) async {
    final result = await api.files.list(
      q: "name = '$filename'",
      spaces: _kAppDataFolderName,
      $fields: 'files(id)',
    );
    return result.files?.firstOrNull?.id;
  }
}
