import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';

class FirebaseUploadResult {
  final bool success;
  final String? error;

  const FirebaseUploadResult({required this.success, this.error});
}

class FirebaseUploadService {
  bool get isConfigured {
    try {
      Firebase.app();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Upload just the raw CSV immediately after measurement, before protocol.
  Future<FirebaseUploadResult> uploadRawMeasurement({
    required String csvContent,
    required String measurementName,
  }) async {
    if (!isConfigured) {
      return const FirebaseUploadResult(
        success: false,
        error: 'Firebase nicht konfiguriert',
      );
    }

    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final safeName = measurementName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final storagePath = 'rohdaten/${timestamp}_$safeName';

      final csvBytes = utf8.encode(csvContent);
      final csvRef = storage.ref('$storagePath/messdaten.csv');
      await csvRef.putData(csvBytes, SettableMetadata(contentType: 'text/csv'));

      await firestore.collection('rohdaten').add({
        'name': measurementName,
        'uploadedAt': FieldValue.serverTimestamp(),
        'storagePath': storagePath,
        'csvSha256': sha256.convert(csvBytes).toString(),
      });

      return const FirebaseUploadResult(success: true);
    } catch (e) {
      return FirebaseUploadResult(success: false, error: e.toString());
    }
  }

  /// Upload complete protocol (PDF + CSV + metadata) after form is filled.
  Future<FirebaseUploadResult> uploadProtocol({
    required String pdfPath,
    required String csvContent,
    required ProtocolData protocolData,
    required String folderName,
  }) async {
    if (!isConfigured) {
      return const FirebaseUploadResult(
        success: false,
        error: 'Firebase nicht konfiguriert',
      );
    }

    try {
      final storage = FirebaseStorage.instance;
      final firestore = FirebaseFirestore.instance;
      final storagePath = 'protokolle/$folderName';

      final pdfFile = File(pdfPath);
      if (pdfFile.existsSync()) {
        final pdfRef = storage.ref('$storagePath/protokoll.pdf');
        await pdfRef.putFile(pdfFile);
      }

      final csvBytes = utf8.encode(csvContent);
      final csvRef = storage.ref('$storagePath/messdaten.csv');
      await csvRef.putData(csvBytes, SettableMetadata(contentType: 'text/csv'));

      final csvHash = sha256.convert(csvBytes).toString();
      final metadata = {
        'version': '2.3',
        'createdAt': FieldValue.serverTimestamp(),
        'object': protocolData.objectName,
        'project': protocolData.projectName,
        'author': protocolData.author,
        'technician': protocolData.technicianName,
        'location': protocolData.location,
        'latitude': protocolData.latitude,
        'longitude': protocolData.longitude,
        'measurement': {
          'filename': protocolData.measurement.filename,
          'startTime': protocolData.measurement.startTime.toIso8601String(),
          'endTime': protocolData.measurement.endTime.toIso8601String(),
          'durationSeconds': protocolData.measurement.duration.inSeconds,
          'sampleCount': protocolData.measurement.samples.length,
        },
        'validation': {
          'nominalPressure': protocolData.nominalPressure,
          'testMedium': protocolData.testMedium.name,
          'testPressure': protocolData.testPressure,
          'passed': protocolData.passed,
          'result': protocolData.result,
          'reason': protocolData.validationReason,
        },
        'storagePath': storagePath,
        'csvSha256': csvHash,
      };

      await firestore.collection('protokolle').doc(folderName).set(metadata);

      return const FirebaseUploadResult(success: true);
    } catch (e) {
      return FirebaseUploadResult(
        success: false,
        error: e.toString(),
      );
    }
  }
}
