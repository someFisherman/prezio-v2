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

class RecordingStatus {
  final bool isRecording;
  final String? name;
  final int? pn;
  final String? medium;
  final double? intervalS;
  final int? elapsedSeconds;
  final int? sampleCount;
  final bool sensorConnected;
  final double? lastP1;
  final double? lastTob1;

  const RecordingStatus({
    required this.isRecording,
    this.name,
    this.pn,
    this.medium,
    this.intervalS,
    this.elapsedSeconds,
    this.sampleCount,
    this.sensorConnected = false,
    this.lastP1,
    this.lastTob1,
  });

  factory RecordingStatus.fromJson(Map<String, dynamic> json) {
    return RecordingStatus(
      isRecording: json['recording'] == true,
      name: json['name'] as String?,
      pn: json['pn'] as int?,
      medium: json['medium'] as String?,
      intervalS: (json['interval_s'] as num?)?.toDouble(),
      elapsedSeconds: json['elapsed_seconds'] as int?,
      sampleCount: json['sample_count'] as int?,
      sensorConnected: json['sensor_connected'] == true,
      lastP1: (json['last_p1'] as num?)?.toDouble(),
      lastTob1: (json['last_tob1'] as num?)?.toDouble(),
    );
  }

  String get elapsedFormatted {
    if (elapsedSeconds == null) return '-';
    final h = elapsedSeconds! ~/ 3600;
    final m = (elapsedSeconds! % 3600) ~/ 60;
    final s = elapsedSeconds! % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }
}

class HealthStatus {
  final bool ok;
  final bool sensorConnected;
  final String? serialNumber;
  final String? sensorPort;
  final bool isRecording;

  const HealthStatus({
    required this.ok,
    this.sensorConnected = false,
    this.serialNumber,
    this.sensorPort,
    this.isRecording = false,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      ok: json['status'] == 'ok',
      sensorConnected: json['sensor_connected'] == true,
      serialNumber: json['serial_number'] as String?,
      sensorPort: json['sensor_port'] as String?,
      isRecording: json['recording'] == true,
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

  Future<HealthStatus?> getHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(AppConstants.connectionTimeout);
      if (response.statusCode == 200) {
        return HealthStatus.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      return null;
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

  Future<bool> deleteFile(String filename) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/files/$filename'))
          .timeout(AppConstants.requestTimeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> startRecording({
    required String name,
    required int pn,
    required String medium,
    double intervalS = 10,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/recording/start'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'name': name,
              'pn': pn,
              'medium': medium,
              'interval_s': intervalS,
            }),
          )
          .timeout(AppConstants.requestTimeout);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> stopRecording() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/recording/stop'))
          .timeout(AppConstants.requestTimeout);

      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<RecordingStatus?> getRecordingStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/recording/status'))
          .timeout(AppConstants.requestTimeout);

      if (response.statusCode == 200) {
        return RecordingStatus.fromJson(json.decode(response.body));
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
