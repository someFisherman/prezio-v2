import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../models/models.dart';

class SupabaseUploadResult {
  final bool success;
  final String? error;

  const SupabaseUploadResult({required this.success, this.error});
}

/// Uploads to Supabase via pure REST API - no SDK, no extra packages.
/// Metadata + CSV in tables, PDFs in Storage.
class SupabaseUploadService {
  bool get isConfigured => SupabaseConfig.isConfigured;

  Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };

  String get _restUrl => '${SupabaseConfig.url}/rest/v1';
  String get _storageUrl => '${SupabaseConfig.url}/storage/v1';

  /// Upload raw CSV immediately after measurement, before protocol form.
  Future<SupabaseUploadResult> uploadRawMeasurement({
    required String csvContent,
    required String measurementName,
  }) async {
    if (!isConfigured) {
      return const SupabaseUploadResult(
        success: false,
        error: 'Supabase nicht konfiguriert',
      );
    }

    try {
      final csvHash = sha256.convert(utf8.encode(csvContent)).toString();

      final response = await http.post(
        Uri.parse('$_restUrl/rohdaten'),
        headers: _headers,
        body: jsonEncode({
          'name': measurementName,
          'csv': csvContent,
          'csv_sha256': csvHash,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const SupabaseUploadResult(success: true);
      }
      return SupabaseUploadResult(
        success: false,
        error: 'HTTP ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      return SupabaseUploadResult(success: false, error: e.toString());
    }
  }

  /// Upload complete protocol: metadata + CSV in table, PDF in Storage.
  Future<SupabaseUploadResult> uploadProtocol({
    required String pdfPath,
    required String csvContent,
    required ProtocolData protocolData,
    required String folderName,
  }) async {
    if (!isConfigured) {
      return const SupabaseUploadResult(
        success: false,
        error: 'Supabase nicht konfiguriert',
      );
    }

    try {
      final csvHash = sha256.convert(utf8.encode(csvContent)).toString();
      String? pdfStoragePath;

      // 1. Upload PDF to Storage (unique name per upload)
      final ts = DateTime.now().millisecondsSinceEpoch;
      final pdfFile = File(pdfPath);
      if (pdfFile.existsSync()) {
        pdfStoragePath = '$folderName/protokoll_$ts.pdf';
        final pdfBytes = await pdfFile.readAsBytes();
        final uploadRes = await http.post(
          Uri.parse('$_storageUrl/object/${SupabaseConfig.bucket}/$pdfStoragePath'),
          headers: {
            'apikey': SupabaseConfig.anonKey,
            'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
            'Content-Type': 'application/pdf',
            'x-upsert': 'true',
          },
          body: pdfBytes,
        );
        if (uploadRes.statusCode < 200 || uploadRes.statusCode >= 300) {
          pdfStoragePath = null;
        }
      }

      // 2. Upload CSV to Storage
      final csvStoragePath = '$folderName/messdaten_$ts.csv';
      await http.post(
        Uri.parse('$_storageUrl/object/${SupabaseConfig.bucket}/$csvStoragePath'),
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
          'Content-Type': 'text/csv',
          'x-upsert': 'true',
        },
        body: utf8.encode(csvContent),
      );

      // 3. Insert metadata row in table
      final row = {
        'folder_name': folderName,
        'version': '2.3',
        'object_name': protocolData.objectName,
        'project': protocolData.projectName,
        'author': protocolData.author,
        'technician': protocolData.technicianName,
        'location': protocolData.location,
        'latitude': protocolData.latitude,
        'longitude': protocolData.longitude,
        'measurement_filename': protocolData.measurement.filename,
        'start_time': protocolData.measurement.startTime.toIso8601String(),
        'end_time': protocolData.measurement.endTime.toIso8601String(),
        'duration_seconds': protocolData.measurement.duration.inSeconds,
        'sample_count': protocolData.measurement.samples.length,
        'nominal_pressure': protocolData.nominalPressure,
        'test_medium': protocolData.testMedium.name,
        'test_pressure': protocolData.testPressure,
        'passed': protocolData.passed,
        'result': protocolData.result,
        'validation_reason': protocolData.validationReason,
        'test_profile_id': protocolData.testProfileId,
        'test_profile_name': protocolData.testProfileName,
        'detected_hold_duration_hours': protocolData.detectedHoldDurationHours,
        'pressure_drop_bar': protocolData.pressureDropBar,
        'failure_reasons': protocolData.failureReasons.isNotEmpty
            ? protocolData.failureReasons.join('; ')
            : null,
        'csv_sha256': csvHash,
        'pdf_path': pdfStoragePath,
      };

      final response = await http.post(
        Uri.parse('$_restUrl/protokolle'),
        headers: _headers,
        body: jsonEncode(row),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const SupabaseUploadResult(success: true);
      }
      return SupabaseUploadResult(
        success: false,
        error: 'HTTP ${response.statusCode}: ${response.body}',
      );
    } catch (e) {
      return SupabaseUploadResult(success: false, error: e.toString());
    }
  }
}
