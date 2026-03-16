import '../models/models.dart';
import 'csv_parser_service.dart';
import 'recorder_connection_service.dart';

class MeasurementService {
  final CsvParserService _csvParser = CsvParserService();
  final RecorderConnectionService _recorderConnection = RecorderConnectionService();
  
  final List<Measurement> _measurements = [];

  List<Measurement> get allMeasurements => List.unmodifiable(_measurements);
  
  List<Measurement> get validMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.valid).toList();
  
  List<Measurement> get invalidMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.invalid).toList();
  
  List<Measurement> get pendingMeasurements => 
      _measurements.where((m) => m.validationStatus == ValidationStatus.pending).toList();

  RecorderConnectionService get recorderConnection => _recorderConnection;

  @Deprecated('Use recorderConnection instead')
  RecorderConnectionService get piConnection => _recorderConnection;

  void updateRecorderConnection(String address, int port) {
    _recorderConnection.updateConnection(address, port);
  }

  @Deprecated('Use updateRecorderConnection instead')
  void updatePiConnection(String address, int port) {
    updateRecorderConnection(address, port);
  }

  Future<bool> checkRecorderConnection() {
    return _recorderConnection.checkConnection();
  }

  @Deprecated('Use checkRecorderConnection instead')
  Future<bool> checkPiConnection() {
    return checkRecorderConnection();
  }

  Future<List<FileInfo>> listRecorderFiles() {
    return _recorderConnection.listFiles();
  }

  @Deprecated('Use listRecorderFiles instead')
  Future<List<FileInfo>> listPiFiles() {
    return listRecorderFiles();
  }

  Future<Measurement?> loadSingleFromRecorder(FileInfo file) async {
    final content = await _recorderConnection.downloadFile(file.filename);
    if (content == null) return null;

    final measurement = _csvParser.parseFromString(content, filename: file.filename);
    if (measurement != null) {
      _addMeasurement(measurement);
    }
    return measurement;
  }

  @Deprecated('Use loadSingleFromRecorder instead')
  Future<Measurement?> loadSingleFromPi(FileInfo file) {
    return loadSingleFromRecorder(file);
  }

  Future<int> loadSelectedFromRecorder(List<FileInfo> files) async {
    int loadedCount = 0;

    for (final file in files) {
      if (!file.filename.endsWith('.csv')) continue;
      final content = await _recorderConnection.downloadFile(file.filename);
      if (content != null) {
        final measurement = _csvParser.parseFromString(content, filename: file.filename);
        if (measurement != null) {
          _addMeasurement(measurement);
          loadedCount++;
        }
      }
    }

    return loadedCount;
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
