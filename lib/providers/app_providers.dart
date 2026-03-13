import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/services.dart';
import '../models/models.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

final measurementServiceProvider = Provider<MeasurementService>((ref) {
  return MeasurementService();
});

final pdfGeneratorProvider = Provider<PdfGeneratorService>((ref) {
  return PdfGeneratorService();
});

final emailServiceProvider = Provider<EmailService>((ref) {
  return EmailService();
});

final measurementsProvider = StateNotifierProvider<MeasurementsNotifier, List<Measurement>>((ref) {
  final service = ref.watch(measurementServiceProvider);
  return MeasurementsNotifier(service);
});

class MeasurementsNotifier extends StateNotifier<List<Measurement>> {
  final MeasurementService _service;

  MeasurementsNotifier(this._service) : super([]);

  Future<int> loadFromFiles() async {
    final count = await _service.loadMultipleFromFiles();
    state = _service.allMeasurements;
    return count;
  }

  Future<Measurement?> loadSingleFile() async {
    final measurement = await _service.loadFromFile();
    state = _service.allMeasurements;
    return measurement;
  }

  Future<int> loadFromPi() async {
    final count = await _service.loadFromPi();
    state = _service.allMeasurements;
    return count;
  }

  void setValidationStatus(String id, ValidationStatus status, {String? reason}) {
    _service.setValidationStatus(id, status, reason: reason);
    state = [..._service.allMeasurements];
  }

  void markAllAsValid() {
    _service.markAllAsValid();
    state = [..._service.allMeasurements];
  }

  void removeMeasurement(String id) {
    _service.removeMeasurement(id);
    state = [..._service.allMeasurements];
  }

  void clearAll() {
    _service.clearAll();
    state = [];
  }

  List<Measurement> get validMeasurements => _service.validMeasurements;
  List<Measurement> get invalidMeasurements => _service.invalidMeasurements;
  List<Measurement> get pendingMeasurements => _service.pendingMeasurements;
}

final selectedMeasurementProvider = StateProvider<Measurement?>((ref) => null);

final protocolDataProvider = StateProvider<ProtocolData?>((ref) => null);

final connectionStatusProvider = StateProvider<bool>((ref) => false);

final isLoadingProvider = StateProvider<bool>((ref) => false);
