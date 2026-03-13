import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import 'csv_parser_service.dart';
import 'pi_connection_service.dart';

class MeasurementService {
  final CsvParserService _csvParser = CsvParserService();
  final PiConnectionService _piConnection = PiConnectionService();
  
  final List<Measurement> _measurements = [];

  List<Measurement> get allMeasurements => List.unmodifiable(_measurements);
  
  List<Measurement> get validMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.valid).toList();
  
  List<Measurement> get invalidMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.invalid).toList();
  
  List<Measurement> get pendingMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.pending).toList();

  void updatePiConnection(String address, int port) {
    _piConnection.updateConnection(address, port);
  }

  Future<bool> checkPiConnection() {
    return _piConnection.checkConnection();
  }

  Future<int> loadFromPi() async {
    final csvContents = await _piConnection.downloadAllFiles();
    int loadedCount = 0;

    for (final content in csvContents) {
      final measurement = _csvParser.parseFromString(content);
      if (measurement != null) {
        _addMeasurement(measurement);
        loadedCount++;
      }
    }

    return loadedCount;
  }

  Future<Measurement?> loadFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;
      String content;

      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        return null;
      }

      final measurement = _csvParser.parseFromString(
        content,
        filename: file.name,
      );

      if (measurement != null) {
        _addMeasurement(measurement);
      }

      return measurement;
    } catch (e) {
      return null;
    }
  }

  Future<int> loadMultipleFromFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return 0;
      }

      int loadedCount = 0;

      for (final file in result.files) {
        String content;

        if (file.bytes != null) {
          content = String.fromCharCodes(file.bytes!);
        } else if (file.path != null) {
          content = await File(file.path!).readAsString();
        } else {
          continue;
        }

        final measurement = _csvParser.parseFromString(
          content,
          filename: file.name,
        );

        if (measurement != null) {
          _addMeasurement(measurement);
          loadedCount++;
        }
      }

      return loadedCount;
    } catch (e) {
      return 0;
    }
  }

  void _addMeasurement(Measurement measurement) {
    final existingIndex = _measurements.indexWhere((m) => m.filename == measurement.filename);
    if (existingIndex >= 0) {
      _measurements[existingIndex] = measurement;
    } else {
      _measurements.add(measurement);
    }
  }

  void setValidationStatus(String measurementId, ValidationStatus status, {String? reason}) {
    final index = _measurements.indexWhere((m) => m.id == measurementId);
    if (index >= 0) {
      _measurements[index] = _measurements[index].copyWith(
        validationStatus: status,
        validationReason: reason,
      );
    }
  }

  void markAllAsValid() {
    for (int i = 0; i < _measurements.length; i++) {
      if (_measurements[i].validationStatus == ValidationStatus.pending) {
        _measurements[i] = _measurements[i].copyWith(
          validationStatus: ValidationStatus.valid,
        );
      }
    }
  }

  void removeMeasurement(String measurementId) {
    _measurements.removeWhere((m) => m.id == measurementId);
  }

  void clearAll() {
    _measurements.clear();
  }

  Measurement? getMeasurementById(String id) {
    try {
      return _measurements.firstWhere((m) => m.id == id);
    } catch (e) {
      return null;
    }
  }

  String exportToCsv(Measurement measurement) {
    return _csvParser.generateCsvFromMeasurement(measurement);
  }
}
