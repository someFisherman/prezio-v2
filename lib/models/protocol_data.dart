import 'dart:typed_data';
import 'measurement.dart';

enum TestMedium {
  air,
  water,
}

extension TestMediumExtension on TestMedium {
  String get displayName {
    switch (this) {
      case TestMedium.air:
        return 'Luft';
      case TestMedium.water:
        return 'Wasser';
    }
  }

  double testPressureFactor() {
    switch (this) {
      case TestMedium.air:
        return 1.1;
      case TestMedium.water:
        return 1.5;
    }
  }
}

class ProtocolData {
  final Measurement measurement;
  
  final String objectName;
  final String projectName;
  final String author;
  
  final int nominalPressure;
  final TestMedium testMedium;
  final double testPressure;
  final String testDuration;
  
  final String result;
  final bool passed;
  
  final String technicianName;
  final Uint8List? signature;
  final DateTime? signatureDate;
  
  final Uint8List? chartImage;
  
  final String? notes;
  final String? validationReason;

  final String? location;
  final double? latitude;
  final double? longitude;

  final String? testProfileId;
  final String? testProfileName;
  final double detectedHoldDurationHours;
  final double pressureDropBar;
  final List<String> failureReasons;

  const ProtocolData({
    required this.measurement,
    this.objectName = '',
    this.projectName = '',
    this.author = '',
    this.nominalPressure = 0,
    this.testMedium = TestMedium.air,
    this.testPressure = 0.0,
    this.testDuration = '',
    this.result = '',
    this.passed = false,
    this.technicianName = '',
    this.signature,
    this.signatureDate,
    this.chartImage,
    this.notes,
    this.validationReason,
    this.location,
    this.latitude,
    this.longitude,
    this.testProfileId,
    this.testProfileName,
    this.detectedHoldDurationHours = 0.0,
    this.pressureDropBar = 0.0,
    this.failureReasons = const [],
  });

  ProtocolData copyWith({
    Measurement? measurement,
    String? objectName,
    String? projectName,
    String? author,
    int? nominalPressure,
    TestMedium? testMedium,
    double? testPressure,
    String? testDuration,
    String? result,
    bool? passed,
    String? technicianName,
    Uint8List? signature,
    DateTime? signatureDate,
    Uint8List? chartImage,
    String? notes,
    String? validationReason,
    String? location,
    double? latitude,
    double? longitude,
    String? testProfileId,
    String? testProfileName,
    double? detectedHoldDurationHours,
    double? pressureDropBar,
    List<String>? failureReasons,
  }) {
    return ProtocolData(
      measurement: measurement ?? this.measurement,
      objectName: objectName ?? this.objectName,
      projectName: projectName ?? this.projectName,
      author: author ?? this.author,
      nominalPressure: nominalPressure ?? this.nominalPressure,
      testMedium: testMedium ?? this.testMedium,
      testPressure: testPressure ?? this.testPressure,
      testDuration: testDuration ?? this.testDuration,
      result: result ?? this.result,
      passed: passed ?? this.passed,
      technicianName: technicianName ?? this.technicianName,
      signature: signature ?? this.signature,
      signatureDate: signatureDate ?? this.signatureDate,
      chartImage: chartImage ?? this.chartImage,
      notes: notes ?? this.notes,
      validationReason: validationReason ?? this.validationReason,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      testProfileId: testProfileId ?? this.testProfileId,
      testProfileName: testProfileName ?? this.testProfileName,
      detectedHoldDurationHours: detectedHoldDurationHours ?? this.detectedHoldDurationHours,
      pressureDropBar: pressureDropBar ?? this.pressureDropBar,
      failureReasons: failureReasons ?? this.failureReasons,
    );
  }
}
