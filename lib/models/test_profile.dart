import 'protocol_data.dart';

enum TestPressureMode { fixed, factor }

class TestProfile {
  final String id;
  final String name;
  final String description;
  final TestMedium medium;
  final TestPressureMode testPressureMode;
  final double? fixedTestPressureBar;
  final double pressureFactor;
  final double holdDurationHours;
  final double minValidPressureRatio;
  final double maxPressureDropBar;
  final int maxDataGapSeconds;
  final bool isCustom;

  const TestProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.medium,
    this.testPressureMode = TestPressureMode.factor,
    this.fixedTestPressureBar,
    this.pressureFactor = 1.0,
    this.holdDurationHours = 1.0,
    this.minValidPressureRatio = 0.98,
    this.maxPressureDropBar = 0.2,
    this.maxDataGapSeconds = 60,
    this.isCustom = false,
  });

  double getRequiredPressure(int pn) {
    if (testPressureMode == TestPressureMode.fixed &&
        fixedTestPressureBar != null) {
      return fixedTestPressureBar!;
    }
    return pn * pressureFactor;
  }

  TestProfile copyWith({
    String? id,
    String? name,
    String? description,
    TestMedium? medium,
    TestPressureMode? testPressureMode,
    double? fixedTestPressureBar,
    double? pressureFactor,
    double? holdDurationHours,
    double? minValidPressureRatio,
    double? maxPressureDropBar,
    int? maxDataGapSeconds,
    bool? isCustom,
  }) {
    return TestProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      medium: medium ?? this.medium,
      testPressureMode: testPressureMode ?? this.testPressureMode,
      fixedTestPressureBar: fixedTestPressureBar ?? this.fixedTestPressureBar,
      pressureFactor: pressureFactor ?? this.pressureFactor,
      holdDurationHours: holdDurationHours ?? this.holdDurationHours,
      minValidPressureRatio:
          minValidPressureRatio ?? this.minValidPressureRatio,
      maxPressureDropBar: maxPressureDropBar ?? this.maxPressureDropBar,
      maxDataGapSeconds: maxDataGapSeconds ?? this.maxDataGapSeconds,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  static const List<int> pnValues = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100];

  static final List<TestProfile> defaultProfiles = [
    const TestProfile(
      id: 'water_standard',
      name: 'Wasser Standard',
      description: 'Wasserdruckpruefung, 1.5x PN, 1h Haltezeit',
      medium: TestMedium.water,
      pressureFactor: 1.5,
      holdDurationHours: 1.0,
      minValidPressureRatio: 0.98,
      maxPressureDropBar: 0.2,
      maxDataGapSeconds: 60,
    ),
    const TestProfile(
      id: 'air_standard',
      name: 'Luft Standard',
      description: 'Luftdruckpruefung, 1.1x PN, 1h Haltezeit',
      medium: TestMedium.air,
      pressureFactor: 1.1,
      holdDurationHours: 1.0,
      minValidPressureRatio: 0.98,
      maxPressureDropBar: 0.1,
      maxDataGapSeconds: 60,
    ),
    const TestProfile(
      id: 'water_longterm',
      name: 'Wasser Langzeit',
      description: 'Wasserdruckpruefung, 1.5x PN, 24h Haltezeit',
      medium: TestMedium.water,
      pressureFactor: 1.5,
      holdDurationHours: 24.0,
      minValidPressureRatio: 0.98,
      maxPressureDropBar: 0.3,
      maxDataGapSeconds: 120,
    ),
    const TestProfile(
      id: 'air_longterm',
      name: 'Luft Langzeit',
      description: 'Luftdruckpruefung, 1.1x PN, 24h Haltezeit',
      medium: TestMedium.air,
      pressureFactor: 1.1,
      holdDurationHours: 24.0,
      minValidPressureRatio: 0.97,
      maxPressureDropBar: 0.15,
      maxDataGapSeconds: 120,
    ),
    const TestProfile(
      id: 'custom',
      name: 'Benutzerdefiniert',
      description: 'Alle Parameter manuell einstellen',
      medium: TestMedium.water,
      pressureFactor: 1.5,
      holdDurationHours: 1.0,
      minValidPressureRatio: 0.98,
      maxPressureDropBar: 0.2,
      maxDataGapSeconds: 60,
      isCustom: true,
    ),
  ];

  static TestProfile? findForMedium(TestMedium medium) {
    return defaultProfiles.firstWhere(
      (p) => p.medium == medium && !p.isCustom && p.holdDurationHours <= 1.0,
      orElse: () => defaultProfiles.first,
    );
  }
}
