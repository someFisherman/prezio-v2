import 'dart:typed_data';
import 'measurement.dart';

enum TestType {
  optical,
  leakSpray,
  xray,
  vacuum,
}

extension TestTypeExtension on TestType {
  String get displayName {
    switch (this) {
      case TestType.optical:
        return 'Optisch';
      case TestType.leakSpray:
        return 'Lecksuchspray';
      case TestType.xray:
        return 'Röntgenprüfung';
      case TestType.vacuum:
        return 'Vakuumtest';
    }
  }
}

enum TestMedium {
  air,
  water,
  nitrogen,
}

extension TestMediumExtension on TestMedium {
  String get displayName {
    switch (this) {
      case TestMedium.air:
        return 'Luft';
      case TestMedium.water:
        return 'Wasser';
      case TestMedium.nitrogen:
        return 'Stickstoff';
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
  
  final List<TestType> testTypes;
  
  final String result;
  final bool passed;
  
  final String technicianName;
  final Uint8List? signature;
  final DateTime? signatureDate;
  
  final Uint8List? chartImage;
  
  final String? notes;

  const ProtocolData({
    required this.measurement,
    this.objectName = '',
    this.projectName = '',
    this.author = '',
    this.nominalPressure = 0,
    this.testMedium = TestMedium.air,
    this.testPressure = 0.0,
    this.testDuration = '',
    this.testTypes = const [],
    this.result = '',
    this.passed = false,
    this.technicianName = '',
    this.signature,
    this.signatureDate,
    this.chartImage,
    this.notes,
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
    List<TestType>? testTypes,
    String? result,
    bool? passed,
    String? technicianName,
    Uint8List? signature,
    DateTime? signatureDate,
    Uint8List? chartImage,
    String? notes,
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
      testTypes: testTypes ?? this.testTypes,
      result: result ?? this.result,
      passed: passed ?? this.passed,
      technicianName: technicianName ?? this.technicianName,
      signature: signature ?? this.signature,
      signatureDate: signatureDate ?? this.signatureDate,
      chartImage: chartImage ?? this.chartImage,
      notes: notes ?? this.notes,
    );
  }
}
