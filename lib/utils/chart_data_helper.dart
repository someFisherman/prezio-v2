import 'dart:math';
import '../models/models.dart';

/// Hilfsklasse für Chart-Daten (Downsampling, Moving Average).
/// Wird von PressureChart und PdfGeneratorService genutzt.
class ChartDataHelper {
  static const int maxPoints = 120;
  static const int movingAverageWindow = 7;

  /// (x in Sekunden, y in bar)
  static List<({double x, double y})> smoothedPressureSpots(Measurement m) {
    final raw = _downsampledSpots(m, (s) => s.pressureRounded);
    return _movingAverage(raw);
  }

  /// Temperatur auf Druck-Skala gemappt für rechte Y-Achse
  static List<({double x, double y})> smoothedTempSpots(
    Measurement m,
    double pMin,
    double pMax,
  ) {
    final tMin = m.minTemperature;
    final tMax = m.maxTemperature;
    final tRange = tMax - tMin;
    final pRange = pMax - pMin;

    final raw = _downsampledSpots(m, (s) {
      if (tRange < 0.01) return (pMin + pMax) / 2;
      return pMin + (s.temperatureRounded - tMin) / tRange * pRange;
    });
    return _movingAverage(raw);
  }

  static List<({double x, double y})> _downsampledSpots(
    Measurement m,
    double Function(Sample s) yFn,
  ) {
    final all = m.samples;
    if (all.isEmpty) return [];
    if (all.length <= maxPoints) {
      return all.map((s) {
        final x =
            s.timestamp.difference(m.startTime).inSeconds.toDouble();
        return (x: x, y: yFn(s));
      }).toList();
    }

    final spots = <({double x, double y})>[];
    final bucketSize = all.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final start = (i * bucketSize).floor();
      final end = ((i + 1) * bucketSize).floor().clamp(0, all.length);
      if (start >= end) continue;

      double ySum = 0;
      double xSum = 0;
      for (int j = start; j < end; j++) {
        ySum += yFn(all[j]);
        xSum += all[j].timestamp.difference(m.startTime).inSeconds.toDouble();
      }
      final count = end - start;
      spots.add((x: xSum / count, y: ySum / count));
    }
    return spots;
  }

  static List<({double x, double y})> _movingAverage(
    List<({double x, double y})> spots,
  ) {
    if (spots.length < movingAverageWindow) return spots;
    final half = movingAverageWindow ~/ 2;
    final result = <({double x, double y})>[];
    for (int i = 0; i < spots.length; i++) {
      final lo = max(0, i - half);
      final hi = min(spots.length - 1, i + half);
      double ySum = 0;
      double wSum = 0;
      for (int j = lo; j <= hi; j++) {
        final w = 1.0 + half - (i - j).abs();
        ySum += spots[j].y * w;
        wSum += w;
      }
      result.add((x: spots[i].x, y: ySum / wSum));
    }
    return result;
  }

  static double roundedMinY(Measurement m) {
    final minP = m.minPressure;
    final range = m.maxPressure - minP;
    final padding = max(range * 0.15, 0.5);
    final raw = minP - padding;
    final step = _niceInterval(range + 2 * padding);
    return (raw / step).floor() * step;
  }

  static double roundedMaxY(Measurement m) {
    final maxP = m.maxPressure;
    final range = maxP - m.minPressure;
    final padding = max(range * 0.15, 0.5);
    final raw = maxP + padding;
    final step = _niceInterval(range + 2 * padding);
    return (raw / step).ceil() * step;
  }

  static double niceInterval(double range) => _niceInterval(range);

  static double _niceInterval(double range) {
    if (range <= 0) return 1.0;
    final rough = range / 5;
    final mag = pow(10, (log(rough) / ln10).floor()).toDouble();
    final norm = rough / mag;
    double nice;
    if (norm < 1.5) {
      nice = 1;
    } else if (norm < 3) {
      nice = 2;
    } else if (norm < 7) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * mag;
  }
}
