import 'dart:math';
import '../models/models.dart';
import 'weather_service.dart';

class ValidationResult {
  final bool valid;
  final String reason;
  final double pExpected;
  final double error;
  final double tolerance;
  final double testPressure;
  final WeatherData? weatherData;

  const ValidationResult({
    required this.valid,
    required this.reason,
    this.pExpected = 0.0,
    this.error = 0.0,
    this.tolerance = 0.0,
    this.testPressure = 0.0,
    this.weatherData,
  });
}

class ValidationService {
  static const List<int> pnValues = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100];

  static double getTestPressure(int pn, TestMedium medium) {
    return pn * medium.testPressureFactor();
  }

  ValidationResult validate(
    Measurement measurement,
    int pn,
    TestMedium medium, {
    WeatherData? weather,
  }) {
    if (measurement.samples.length < 5) {
      return const ValidationResult(
        valid: false,
        reason: 'Zu wenige Messpunkte (mindestens 5 erforderlich).',
      );
    }

    final p0 = measurement.samples.first.pressureRounded;
    final p1 = measurement.samples.last.pressureRounded;
    final t0 = measurement.samples.first.temperatureRounded;
    final t1 = measurement.samples.last.temperatureRounded;
    final testPressure = getTestPressure(pn, medium);

    if (p0 > 1.5 * pn || p1 > 1.5 * pn) {
      return ValidationResult(
        valid: false,
        reason: 'Sicherheitsgrenze ueberschritten: Druck > ${(1.5 * pn).toStringAsFixed(1)} bar (1.5 x PN$pn).',
        testPressure: testPressure,
        weatherData: weather,
      );
    }

    double pExpected;
    if (medium == TestMedium.air) {
      pExpected = p0 * (t1 + 273.15) / (t0 + 273.15);
    } else {
      pExpected = p0 + (0.003 * p0 * (t1 - t0));
    }

    double baseTolerance = max(0.02 * p0, 0.1);

    // Weather-adjusted tolerance: outdoor temp swings cause pressure
    // variations in exposed pipe sections that the sensor may not fully capture.
    double weatherAdjustment = 0.0;
    String weatherNote = '';
    if (weather != null && weather.fromApi) {
      weatherAdjustment = weather.additionalTolerance * p0;
      if (weatherAdjustment > 0) {
        weatherNote = ' (inkl. ${weatherAdjustment.toStringAsFixed(3)} bar Wetter-Toleranz '
            'fuer ${weather.tempSwing.toStringAsFixed(1)}°C Aussenschwankung)';
      }
    }

    final tolerance = baseTolerance + weatherAdjustment;
    final error = (p1 - pExpected).abs();
    final valid = error <= tolerance;

    final reason = valid
        ? 'Pruefung bestanden. Druckaenderung im erwarteten Bereich '
          '(Abweichung: ${error.toStringAsFixed(3)} bar, Toleranz: ${tolerance.toStringAsFixed(3)} bar).$weatherNote'
        : 'Pruefung nicht bestanden. Druckverlust groesser als erwartet '
          '(Abweichung: ${error.toStringAsFixed(3)} bar, Toleranz: ${tolerance.toStringAsFixed(3)} bar). '
          'Moegliche Leckage.$weatherNote';

    return ValidationResult(
      valid: valid,
      reason: reason,
      pExpected: pExpected,
      error: error,
      tolerance: tolerance,
      testPressure: testPressure,
      weatherData: weather,
    );
  }
}
