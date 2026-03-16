import 'dart:math';
import '../models/models.dart';
import 'weather_service.dart';

class ValidationResult {
  final bool isValidMeasurement;
  final bool isPassed;
  final double requiredPressureBar;
  final double detectedHoldDurationHours;
  final double pressureDropBar;
  final DateTime? evaluationWindowStart;
  final DateTime? evaluationWindowEnd;
  final List<String> failureReasons;
  final String profileName;
  final WeatherData? weatherData;

  const ValidationResult({
    required this.isValidMeasurement,
    required this.isPassed,
    this.requiredPressureBar = 0.0,
    this.detectedHoldDurationHours = 0.0,
    this.pressureDropBar = 0.0,
    this.evaluationWindowStart,
    this.evaluationWindowEnd,
    this.failureReasons = const [],
    this.profileName = '',
    this.weatherData,
  });

  /// Backwards-compatible getters used by existing UI/PDF code.
  bool get valid => isPassed;
  String get reason => failureReasons.isEmpty
      ? 'Pruefung bestanden'
      : failureReasons.join('; ');
}

/// A contiguous time window where pressure stayed above the threshold.
class _PlateauSegment {
  final int startIndex;
  final int endIndex;
  final DateTime startTime;
  final DateTime endTime;
  final double maxPressure;
  final double minPressure;

  _PlateauSegment({
    required this.startIndex,
    required this.endIndex,
    required this.startTime,
    required this.endTime,
    required this.maxPressure,
    required this.minPressure,
  });

  Duration get duration => endTime.difference(startTime);
  double get durationHours => duration.inSeconds / 3600.0;
  double get pressureDrop => maxPressure - minPressure;
}

class ValidationService {
  /// Kept for backwards compatibility with RecorderScreen PN dropdown.
  static const List<int> pnValues = TestProfile.pnValues;

  /// Legacy helper - use TestProfile.getRequiredPressure instead.
  static double getTestPressure(int pn, TestMedium medium) {
    final factor = medium == TestMedium.water ? 1.5 : 1.1;
    return pn * factor;
  }

  /// Main validation entry point using the new profile-based logic.
  ValidationResult validate(
    Measurement measurement,
    int pn,
    TestProfile profile, {
    WeatherData? weather,
  }) {
    final reasons = <String>[];
    final requiredPressure = profile.getRequiredPressure(pn);

    // --- Basic sanity checks ---
    if (measurement.samples.length < 5) {
      return ValidationResult(
        isValidMeasurement: false,
        isPassed: false,
        requiredPressureBar: requiredPressure,
        failureReasons: const ['Zu wenige Messpunkte (mindestens 5 erforderlich)'],
        profileName: profile.name,
        weatherData: weather,
      );
    }

    final totalDurationSec = measurement.duration.inSeconds;
    if (totalDurationSec < 10) {
      return ValidationResult(
        isValidMeasurement: false,
        isPassed: false,
        requiredPressureBar: requiredPressure,
        failureReasons: const ['Messzeit zu kurz (< 10 Sekunden)'],
        profileName: profile.name,
        weatherData: weather,
      );
    }

    // --- Weather-adjusted max pressure drop ---
    double adjustedMaxDrop = profile.maxPressureDropBar;
    if (weather != null && weather.fromApi && weather.additionalTolerance > 0) {
      final weatherExtra = weather.additionalTolerance * requiredPressure;
      adjustedMaxDrop += weatherExtra;
    }

    // --- Check if required pressure was ever reached ---
    final threshold = requiredPressure * profile.minValidPressureRatio;
    final peakPressure = measurement.samples
        .map((s) => s.pressureRounded)
        .reduce(max);

    if (peakPressure < threshold) {
      return ValidationResult(
        isValidMeasurement: true,
        isPassed: false,
        requiredPressureBar: requiredPressure,
        failureReasons: [
          'Pruefdruck nicht erreicht '
              '(max ${peakPressure.toStringAsFixed(2)} bar, '
              'erforderlich ${threshold.toStringAsFixed(2)} bar)',
        ],
        profileName: profile.name,
        weatherData: weather,
      );
    }

    // --- Scan for plateau segments ---
    final segments = _findPlateauSegments(
      measurement,
      threshold,
      profile.maxDataGapSeconds,
    );

    if (segments.isEmpty) {
      return ValidationResult(
        isValidMeasurement: true,
        isPassed: false,
        requiredPressureBar: requiredPressure,
        failureReasons: const ['Kein zusammenhaengendes Druckplateau gefunden'],
        profileName: profile.name,
        weatherData: weather,
      );
    }

    // --- Pick the longest valid segment ---
    final best = segments.reduce(
      (a, b) => a.duration >= b.duration ? a : b,
    );

    final holdHours = best.durationHours;
    final drop = best.pressureDrop;

    // --- Evaluate ---
    final holdRequired = profile.holdDurationHours;

    if (holdHours < holdRequired) {
      reasons.add(
        'Haltezeit zu kurz '
        '(${_formatHours(holdHours)} von ${_formatHours(holdRequired)} erforderlich)',
      );
    }

    if (drop > adjustedMaxDrop) {
      reasons.add(
        'Druckabfall zu hoch '
        '(${drop.toStringAsFixed(3)} bar, max ${adjustedMaxDrop.toStringAsFixed(3)} bar erlaubt)',
      );
    }

    // Check data density: at least 1 sample per 2 * expected interval
    final segmentSamples = best.endIndex - best.startIndex + 1;
    final segmentSeconds = best.duration.inSeconds;
    if (segmentSamples < 3) {
      reasons.add('Kein zusammenhaengendes Druckplateau (nur $segmentSamples Messpunkte)');
    } else if (segmentSeconds > 60 && segmentSamples < (segmentSeconds / 120).ceil()) {
      reasons.add('Messdatendichte zu gering im Prueffenster');
    }

    // Check for data gaps within the best segment
    final gapFound = _hasInternalGap(
      measurement,
      best.startIndex,
      best.endIndex,
      profile.maxDataGapSeconds,
    );
    if (gapFound) {
      reasons.add(
        'Messdatenluecken groesser als ${profile.maxDataGapSeconds}s im Prueffenster',
      );
    }

    final isPassed = reasons.isEmpty;

    if (isPassed) {
      String weatherNote = '';
      if (weather != null &&
          weather.fromApi &&
          weather.additionalTolerance > 0) {
        weatherNote =
            ' (Wetter-Korrektur: +${(weather.additionalTolerance * requiredPressure).toStringAsFixed(3)} bar '
            'fuer ${weather.tempSwing.toStringAsFixed(1)}°C Schwankung)';
      }
      reasons.add(
        'Pruefung bestanden. '
        'Haltezeit ${_formatHours(holdHours)}, '
        'Druckabfall ${drop.toStringAsFixed(3)} bar'
        '$weatherNote',
      );
    }

    return ValidationResult(
      isValidMeasurement: true,
      isPassed: isPassed,
      requiredPressureBar: requiredPressure,
      detectedHoldDurationHours: holdHours,
      pressureDropBar: drop,
      evaluationWindowStart: best.startTime,
      evaluationWindowEnd: best.endTime,
      failureReasons: reasons,
      profileName: profile.name,
      weatherData: weather,
    );
  }

  /// Find all contiguous segments where pressure >= threshold,
  /// breaking on data gaps > maxGapSeconds.
  List<_PlateauSegment> _findPlateauSegments(
    Measurement measurement,
    double threshold,
    int maxGapSeconds,
  ) {
    final samples = measurement.samples;
    final segments = <_PlateauSegment>[];

    int? segStart;
    double segMax = 0;
    double segMin = double.infinity;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final aboveThreshold = s.pressureRounded >= threshold;

      // Check for data gap with previous sample
      bool gapBreak = false;
      if (i > 0 && segStart != null) {
        final gap = s.timestamp.difference(samples[i - 1].timestamp).inSeconds;
        if (gap > maxGapSeconds) {
          gapBreak = true;
        }
      }

      if (aboveThreshold && !gapBreak) {
        if (segStart == null) {
          segStart = i;
          segMax = s.pressureRounded;
          segMin = s.pressureRounded;
        } else {
          segMax = max(segMax, s.pressureRounded);
          segMin = min(segMin, s.pressureRounded);
        }
      } else {
        if (segStart != null) {
          segments.add(_PlateauSegment(
            startIndex: segStart,
            endIndex: i - 1,
            startTime: samples[segStart].timestamp,
            endTime: samples[i - 1].timestamp,
            maxPressure: segMax,
            minPressure: segMin,
          ));
          segStart = null;
          segMax = 0;
          segMin = double.infinity;
        }
        // If gap broke us but we're still above threshold, start new segment
        if (aboveThreshold && gapBreak) {
          segStart = i;
          segMax = s.pressureRounded;
          segMin = s.pressureRounded;
        }
      }
    }

    // Close last open segment
    if (segStart != null) {
      final last = samples.length - 1;
      segments.add(_PlateauSegment(
        startIndex: segStart,
        endIndex: last,
        startTime: samples[segStart].timestamp,
        endTime: samples[last].timestamp,
        maxPressure: segMax,
        minPressure: segMin,
      ));
    }

    return segments;
  }

  /// Check whether there is any internal gap > maxGapSeconds within [start..end].
  bool _hasInternalGap(
    Measurement measurement,
    int startIdx,
    int endIdx,
    int maxGapSeconds,
  ) {
    final samples = measurement.samples;
    for (int i = startIdx + 1; i <= endIdx; i++) {
      final gap =
          samples[i].timestamp.difference(samples[i - 1].timestamp).inSeconds;
      if (gap > maxGapSeconds) return true;
    }
    return false;
  }

  String _formatHours(double hours) {
    if (hours < 1.0) {
      final mins = (hours * 60).round();
      return '${mins}min';
    }
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }
}
