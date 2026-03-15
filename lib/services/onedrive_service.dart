import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

class OneDriveUploadResult {
  final bool success;
  final String? error;
  final int filesUploaded;

  const OneDriveUploadResult({
    required this.success,
    this.error,
    this.filesUploaded = 0,
  });
}

class OneDriveService {
  static const _authorizeUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
  static const _tokenUrl =
      'https://login.microsoftonline.com/common/oauth2/v2.0/token';
  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _scope = 'Files.ReadWrite offline_access';
  static const _callbackScheme = 'prezio';
  static const _redirectUri = 'prezio://auth';

  /// Base folder in OneDrive root
  static const _baseFolderPath = 'Prezio/Protokolle';

  String _clientId = '';
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;

  bool get isConnected => _refreshToken != null && _refreshToken!.isNotEmpty;

  void configure({required String clientId, String? savedRefreshToken}) {
    _clientId = clientId;
    _refreshToken = savedRefreshToken;
  }

  /// Interactive Microsoft login. Returns refresh token to persist, or null on failure.
  Future<String?> login() async {
    if (_clientId.isEmpty) return null;

    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);

    final authUrl = '$_authorizeUrl?'
        'client_id=$_clientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
        '&scope=${Uri.encodeComponent(_scope)}'
        '&code_challenge=$challenge'
        '&code_challenge_method=S256'
        '&prompt=select_account';

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: _callbackScheme,
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) return null;

      final ok = await _exchangeCode(code, verifier);
      return ok ? _refreshToken : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _exchangeCode(String code, String verifier) async {
    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId,
          'code': code,
          'redirect_uri': _redirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
      );

      if (response.statusCode == 200) {
        _parseTokenResponse(jsonDecode(response.body));
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null || _clientId.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId,
          'refresh_token': _refreshToken,
          'grant_type': 'refresh_token',
          'scope': _scope,
        },
      );

      if (response.statusCode == 200) {
        _parseTokenResponse(jsonDecode(response.body));
        return true;
      }
    } catch (_) {}

    _refreshToken = null;
    return false;
  }

  void _parseTokenResponse(Map<String, dynamic> data) {
    _accessToken = data['access_token'];
    if (data['refresh_token'] != null) {
      _refreshToken = data['refresh_token'];
    }
    _tokenExpiry = DateTime.now()
        .add(Duration(seconds: (data['expires_in'] as int?) ?? 3600));
  }

  Future<bool> _ensureToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return true;
    }
    return await _refreshAccessToken();
  }

  Future<bool> _uploadBytes(String remotePath, List<int> bytes,
      {String contentType = 'application/octet-stream'}) async {
    if (!await _ensureToken()) return false;

    try {
      final response = await http.put(
        Uri.parse('$_graphBase/me/drive/root:/$remotePath:/content'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': contentType,
        },
        body: bytes,
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Upload a complete protocol folder to OneDrive.
  /// Path: OneDrive > Prezio > Protokolle > {folderName} > files
  Future<OneDriveUploadResult> uploadProtocol({
    required String folderName,
    required String pdfPath,
    String? csvContent,
    required String metadataJson,
  }) async {
    if (!isConnected) {
      return const OneDriveUploadResult(
        success: false,
        error: 'Nicht mit OneDrive verbunden',
      );
    }

    int uploaded = 0;
    final basePath = '$_baseFolderPath/$folderName';

    // Upload PDF
    final pdfFile = File(pdfPath);
    if (await pdfFile.exists()) {
      final pdfName = pdfPath.split('/').last.split('\\').last;
      final ok = await _uploadBytes(
        '$basePath/$pdfName',
        await pdfFile.readAsBytes(),
      );
      if (!ok) {
        return const OneDriveUploadResult(
          success: false,
          error: 'PDF-Upload fehlgeschlagen',
        );
      }
      uploaded++;
    }

    // Upload CSV
    if (csvContent != null) {
      final ok = await _uploadBytes(
        '$basePath/Messdaten.csv',
        utf8.encode(csvContent),
        contentType: 'text/csv; charset=utf-8',
      );
      if (ok) uploaded++;
    }

    // Upload metadata
    final metaOk = await _uploadBytes(
      '$basePath/metadata.json',
      utf8.encode(metadataJson),
      contentType: 'application/json; charset=utf-8',
    );
    if (metaOk) uploaded++;

    return OneDriveUploadResult(success: true, filesUploaded: uploaded);
  }

  void logout() {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
  }

  String _generateCodeVerifier() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
