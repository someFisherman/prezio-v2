import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class FileInfo {
  final String filename;
  final int size;
  final DateTime? modified;

  FileInfo({
    required this.filename,
    this.size = 0,
    this.modified,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      filename: json['filename'] ?? json['name'] ?? '',
      size: json['size'] ?? 0,
      modified: json['modified'] != null 
          ? DateTime.tryParse(json['modified']) 
          : null,
    );
  }
}

class PiConnectionService {
  String _address;
  int _port;

  PiConnectionService({
    String? address,
    int? port,
  })  : _address = address ?? AppConstants.defaultPiAddress,
        _port = port ?? AppConstants.defaultPiPort;

  String get baseUrl => 'http://$_address:$_port';

  void updateConnection(String address, int port) {
    _address = address;
    _port = port;
  }

  Future<bool> checkConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(AppConstants.connectionTimeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<List<FileInfo>> listFiles() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/files'))
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => FileInfo.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<String?> downloadFile(String filename) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/files/$filename'))
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> downloadAllFiles() async {
    final files = await listFiles();
    final contents = <String>[];

    for (final file in files) {
      if (file.filename.endsWith('.csv')) {
        final content = await downloadFile(file.filename);
        if (content != null) {
          contents.add(content);
        }
      }
    }

    return contents;
  }
}
