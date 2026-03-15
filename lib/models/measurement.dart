import 'sample.dart';

enum ValidationStatus { pending, valid, invalid }

class CsvMetadata {
  final String? name;
  final int? pn;
  final String? medium;
  final double? intervalS;

  const CsvMetadata({this.name, this.pn, this.medium, this.intervalS});

  bool get hasRecordingParams => pn != null && medium != null;
}

class Measurement {
  final String id;
  final String filename;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final List<Sample> samples;
  final ValidationStatus validationStatus;
  final String? validationReason;
  final CsvMetadata? metadata;
  
  double get minPressure => samples.isEmpty 
      ? 0.0 
      : samples.map((s) => s.pressureRounded).reduce((a, b) => a < b ? a : b);
  
  double get maxPressure => samples.isEmpty 
      ? 0.0 
      : samples.map((s) => s.pressureRounded).reduce((a, b) => a > b ? a : b);
  
  double get avgPressure => samples.isEmpty 
      ? 0.0 
      : samples.map((s) => s.pressureRounded).reduce((a, b) => a + b) / samples.length;
  
  double get minTemperature => samples.isEmpty 
      ? 0.0 
      : samples.map((s) => s.temperatureRounded).reduce((a, b) => a < b ? a : b);
  
  double get maxTemperature => samples.isEmpty 
      ? 0.0 
      : samples.map((s) => s.temperatureRounded).reduce((a, b) => a > b ? a : b);

  bool get hasRecordingMetadata => metadata?.hasRecordingParams ?? false;

  const Measurement({
    required this.id,
    required this.filename,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.samples,
    this.validationStatus = ValidationStatus.pending,
    this.validationReason,
    this.metadata,
  });

  Measurement copyWith({
    String? id,
    String? filename,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    List<Sample>? samples,
    ValidationStatus? validationStatus,
    String? validationReason,
    CsvMetadata? metadata,
  }) {
    return Measurement(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      samples: samples ?? this.samples,
      validationStatus: validationStatus ?? this.validationStatus,
      validationReason: validationReason ?? this.validationReason,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'sampleCount': samples.length,
        'validationStatus': validationStatus.name,
        'validationReason': validationReason,
        'minPressure': minPressure,
        'maxPressure': maxPressure,
        'avgPressure': avgPressure,
      };
}
