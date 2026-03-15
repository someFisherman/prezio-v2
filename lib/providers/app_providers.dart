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

final validationServiceProvider = Provider<ValidationService>((ref) {
  return ValidationService();
});

final protocolStorageProvider = Provider<ProtocolStorageService>((ref) {
  return ProtocolStorageService();
});

final weatherServiceProvider = Provider<WeatherService>((ref) {
  return WeatherService();
});

final measurementsProvider = StateNotifierProvider<MeasurementsNotifier, List<Measurement>>((ref) {
  final service = ref.watch(measurementServiceProvider);
  return MeasurementsNotifier(service);
});

class MeasurementsNotifier extends StateNotifier<List<Measurement>> {
  final MeasurementService _service;

  MeasurementsNotifier(this._service) : super([]);

  void refresh() {
    state = [..._service.allMeasurements];
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
}

final selectedMeasurementProvider = StateProvider<Measurement?>((ref) => null);

final protocolDataProvider = StateProvider<ProtocolData?>((ref) => null);
