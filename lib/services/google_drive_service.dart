import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveUploadResult {
  final bool success;
  final String? error;
  final int filesUploaded;

  const GoogleDriveUploadResult({
    required this.success,
    this.error,
    this.filesUploaded = 0,
  });
}

class GoogleDriveService {
  static const _driveScopes = [drive.DriveApi.driveFileScope];

  GoogleSignIn get _signIn => GoogleSignIn.instance;
  bool _initialized = false;
  GoogleSignInAccount? _currentUser;

  bool get isSignedIn => _currentUser != null;
  String? get userName => _currentUser?.displayName;
  String? get userEmail => _currentUser?.email;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _signIn.initialize();
    _signIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _currentUser = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _currentUser = null;
      }
    });
    _initialized = true;
  }

  Future<bool> trySilentSignIn() async {
    await _ensureInitialized();
    final result = await _signIn.attemptLightweightAuthentication();
    if (result != null) {
      _currentUser = result;
    }
    return isSignedIn;
  }

  Future<bool> signIn() async {
    try {
      await _ensureInitialized();
      if (_signIn.supportsAuthenticate()) {
        await _signIn.authenticate();
      }
      return isSignedIn;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await _signIn.signOut();
    _currentUser = null;
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    final user = _currentUser;
    if (user == null) return null;

    try {
      final authorization =
          await user.authorizationClient.authorizeScopes(_driveScopes);
      final authClient = authorization.authClient(scopes: _driveScopes);
      return drive.DriveApi(authClient);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _ensureFolder(
    drive.DriveApi driveApi,
    String name, {
    String? parentId,
  }) async {
    final q = StringBuffer("mimeType='application/vnd.google-apps.folder'");
    q.write(" and name='$name'");
    q.write(" and trashed=false");
    if (parentId != null) {
      q.write(" and '$parentId' in parents");
    }

    final result = await driveApi.files.list(
      q: q.toString(),
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id;
    }

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) {
      folder.parents = [parentId];
    }

    final created = await driveApi.files.create(folder);
    return created.id;
  }

  Future<String?> _ensureProtocolFolder(
    drive.DriveApi driveApi,
    String folderName,
  ) async {
    final prezioId = await _ensureFolder(driveApi, 'Prezio');
    if (prezioId == null) return null;

    final protokolleId = await _ensureFolder(
      driveApi,
      'Protokolle',
      parentId: prezioId,
    );
    if (protokolleId == null) return null;

    return await _ensureFolder(
      driveApi,
      folderName,
      parentId: protokolleId,
    );
  }

  Future<bool> _uploadFile(
    drive.DriveApi driveApi,
    String folderId,
    String fileName,
    List<int> bytes,
    String mimeType,
  ) async {
    try {
      final file = drive.File()
        ..name = fileName
        ..parents = [folderId];

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: mimeType,
      );

      await driveApi.files.create(file, uploadMedia: media);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<GoogleDriveUploadResult> uploadProtocol({
    required String folderName,
    required String pdfPath,
    String? csvContent,
    required String metadataJson,
  }) async {
    if (!isSignedIn) {
      return const GoogleDriveUploadResult(
        success: false,
        error: 'Nicht mit Google angemeldet',
      );
    }

    final driveApi = await _getDriveApi();
    if (driveApi == null) {
      return const GoogleDriveUploadResult(
        success: false,
        error: 'Google Drive Zugriff fehlgeschlagen',
      );
    }

    try {
      final folderId = await _ensureProtocolFolder(driveApi, folderName);
      if (folderId == null) {
        return const GoogleDriveUploadResult(
          success: false,
          error: 'Ordner konnte nicht erstellt werden',
        );
      }

      int uploaded = 0;

      final pdfFile = File(pdfPath);
      if (await pdfFile.exists()) {
        final pdfName = pdfPath.split('/').last.split('\\').last;
        final ok = await _uploadFile(
          driveApi,
          folderId,
          pdfName,
          await pdfFile.readAsBytes(),
          'application/pdf',
        );
        if (!ok) {
          return const GoogleDriveUploadResult(
            success: false,
            error: 'PDF-Upload fehlgeschlagen',
          );
        }
        uploaded++;
      }

      if (csvContent != null) {
        final ok = await _uploadFile(
          driveApi,
          folderId,
          'Messdaten.csv',
          utf8.encode(csvContent),
          'text/csv',
        );
        if (ok) uploaded++;
      }

      final metaOk = await _uploadFile(
        driveApi,
        folderId,
        'metadata.json',
        utf8.encode(metadataJson),
        'application/json',
      );
      if (metaOk) uploaded++;

      return GoogleDriveUploadResult(success: true, filesUploaded: uploaded);
    } catch (e) {
      return GoogleDriveUploadResult(
        success: false,
        error: 'Upload-Fehler: $e',
      );
    }
  }

  Future<bool> checkInternetConnection() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
