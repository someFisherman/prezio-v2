import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class ProtocolStorageResult {
  final String folderPath;
  final String protocolPdfPath;
  final String chartPdfPath;
  final String? csvPath;
  final String metadataPath;
  final bool savedToCustomFolder;

  const ProtocolStorageResult({
    required this.folderPath,
    required this.protocolPdfPath,
    required this.chartPdfPath,
    this.csvPath,
    required this.metadataPath,
    this.savedToCustomFolder = false,
  });

  @Deprecated('Use protocolPdfPath')
  String get pdfPath => protocolPdfPath;
}

class ProtocolStorageService {
  Future<Directory> get _localBaseDir async {
    final dir = await getApplicationDocumentsDirectory();
    final prezioDir = Directory('${dir.path}/Prezio/Protokolle');
    if (!await prezioDir.exists()) {
      await prezioDir.create(recursive: true);
    }
    return prezioDir;
  }

  Future<ProtocolStorageResult> saveProtocol({
    required String protocolPdfPath,
    required String chartPdfPath,
    String? csvContent,
    required ProtocolData protocolData,
    String? customOutputFolder,
  }) async {
    final folderName = _buildFolderName(protocolData);
    final date = Formatters.formatDate(protocolData.measurement.startTime)
        .replaceAll('.', '-');
    final result = protocolData.passed ? 'OK' : 'Nicht_OK';

    // Try custom folder first, fall back to local
    bool savedToCustom = false;
    Directory targetFolder;

    if (customOutputFolder != null) {
      try {
        final customBase = Directory(customOutputFolder);
        if (await customBase.exists()) {
          targetFolder = Directory('${customBase.path}/$folderName');
          if (!await targetFolder.exists()) {
            await targetFolder.create(recursive: true);
          }
          // Test write access
          final testFile = File('${targetFolder.path}/.prezio_test');
          await testFile.writeAsString('test');
          await testFile.delete();
          savedToCustom = true;
        } else {
          targetFolder = await _createLocalFolder(folderName);
        }
      } catch (_) {
        targetFolder = await _createLocalFolder(folderName);
      }
    } else {
      targetFolder = await _createLocalFolder(folderName);
    }

    final protocolDest = '${targetFolder.path}/Druckprotokoll_${date}_$result.pdf';
    final chartDest = '${targetFolder.path}/Druckkurve_${date}_$result.pdf';
    await File(protocolPdfPath).copy(protocolDest);
    await File(chartPdfPath).copy(chartDest);

    String? csvDest;
    String? csvHash;
    if (csvContent != null) {
      csvDest = '${targetFolder.path}/Messdaten_$date.csv';
      await File(csvDest).writeAsString(csvContent);
      csvHash = sha256.convert(utf8.encode(csvContent)).toString();
    }

    final metadata = _buildMetadata(protocolData, csvHash);
    final metadataPath = '${targetFolder.path}/metadata.json';
    await File(metadataPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));

    return ProtocolStorageResult(
      folderPath: targetFolder.path,
      protocolPdfPath: protocolDest,
      chartPdfPath: chartDest,
      csvPath: csvDest,
      metadataPath: metadataPath,
      savedToCustomFolder: savedToCustom,
    );
  }

  Future<Directory> _createLocalFolder(String folderName) async {
    final base = await _localBaseDir;
    final folder = Directory('${base.path}/$folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  String _buildFolderName(ProtocolData data) {
    final date = data.measurement.startTime;
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final objectName = data.objectName.isNotEmpty
        ? _sanitize(data.objectName)
        : 'Unbenannt';
    return '${objectName}_$dateStr';
  }

  String _sanitize(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
  }

  Map<String, dynamic> _buildMetadata(ProtocolData data, String? csvHash) {
    return {
      'version': '2.0',
      'createdAt': DateTime.now().toIso8601String(),
      'object': data.objectName,
      'project': data.projectName,
      'author': data.author,
      'technician': data.technicianName,
      'measurement': {
        'filename': data.measurement.filename,
        'startTime': data.measurement.startTime.toIso8601String(),
        'endTime': data.measurement.endTime.toIso8601String(),
        'durationSeconds': data.measurement.duration.inSeconds,
        'sampleCount': data.measurement.samples.length,
      },
      'validation': {
        'nominalPressure': data.nominalPressure,
        'testMedium': data.testMedium.name,
        'testPressure': data.testPressure,
        'passed': data.passed,
        'result': data.result,
        'reason': data.validationReason,
      },
      'signature': {
        'date': data.signatureDate?.toIso8601String(),
        'hasSignature': data.signature != null,
      },
      if (csvHash != null) 'csvSha256': csvHash,
    };
  }

  Future<List<ProtocolFolder>> listSavedProtocols() async {
    final base = await _localBaseDir;
    final folders = <ProtocolFolder>[];

    if (!await base.exists()) return folders;

    await for (final entity in base.list()) {
      if (entity is Directory) {
        final metaFile = File('${entity.path}/metadata.json');
        if (await metaFile.exists()) {
          try {
            final content = await metaFile.readAsString();
            final meta = json.decode(content) as Map<String, dynamic>;
            folders.add(ProtocolFolder(
              path: entity.path,
              name: entity.path.split(Platform.pathSeparator).last,
              metadata: meta,
            ));
          } catch (_) {}
        }
      }
    }

    folders.sort((a, b) {
      final aTime = a.metadata['createdAt'] as String? ?? '';
      final bTime = b.metadata['createdAt'] as String? ?? '';
      return bTime.compareTo(aTime);
    });

    return folders;
  }
}

class ProtocolFolder {
  final String path;
  final String name;
  final Map<String, dynamic> metadata;

  const ProtocolFolder({
    required this.path,
    required this.name,
    required this.metadata,
  });

  String get objectName => metadata['object'] as String? ?? '';
  String get projectName => metadata['project'] as String? ?? '';
  bool get passed => (metadata['validation'] as Map?)?['passed'] == true;
  String get createdAt => metadata['createdAt'] as String? ?? '';
}
