import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class PressureChart extends StatelessWidget {
  final Measurement measurement;
  final bool showTemperature;
  final double height;

  const PressureChart({
    super.key,
    required this.measurement,
    this.showTemperature = true,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    if (measurement.samples.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Keine Messdaten vorhanden')),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: height,
          child: LineChart(_buildChartData()),
        ),
        if (showTemperature) ...[
          const SizedBox(height: 12),
          _buildLegend(),
        ],
      ],
    );
  }

  LineChartData _buildChartData() {
    final totalSec = measurement.duration.inSeconds.toDouble();
    final pMin = _roundedMinY();
    final pMax = _roundedMaxY();
    final pInterval = _niceInterval(pMax - pMin);
    final tInterval = _timeInterval(totalSec);

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: pInterval,
        verticalInterval: tInterval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.3), strokeWidth: 0.5),
        getDrawingVerticalLine: (_) =>
            FlLine(color: Colors.grey.withValues(alpha: 0.3), strokeWidth: 0.5),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: showTemperature
            ? AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: pInterval,
                  getTitlesWidget: (value, meta) => _tempLabel(value, meta, pMin, pMax),
                ),
              )
            : const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: tInterval,
            getTitlesWidget: _timeLabel,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            interval: pInterval,
            getTitlesWidget: (value, meta) {
              if (value == meta.max || value == meta.min) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(
                  value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.shade400, width: 0.5),
      ),
      minX: 0,
      maxX: totalSec,
      minY: pMin,
      maxY: pMax,
      lineBarsData: [
        _pressureLine(),
        if (showTemperature) _temperatureLine(pMin, pMax),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((spot) {
            final idx = _closestIndex(spot.x.toInt());
            if (idx < 0) return null;
            final s = measurement.samples[idx];
            if (spot.barIndex == 0) {
              return LineTooltipItem(
                '${Formatters.formatPressure(s.pressureRounded)} bar\n'
                '${Formatters.formatTime(s.timestamp)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              );
            }
            return LineTooltipItem(
              '${Formatters.formatTemperature(s.temperatureRounded)} °C',
              const TextStyle(color: Colors.white, fontSize: 12),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- Pressure line ---
  LineChartBarData _pressureLine() {
    final spots = <FlSpot>[];
    for (final s in measurement.samples) {
      final x = s.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      spots.add(FlSpot(x, s.pressureRounded));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.15,
      color: Colors.blue,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: Colors.blue.withValues(alpha: 0.08),
      ),
    );
  }

  // --- Temperature line (mapped to pressure Y axis) ---
  LineChartBarData _temperatureLine(double pMin, double pMax) {
    final spots = <FlSpot>[];
    final tMin = measurement.minTemperature;
    final tMax = measurement.maxTemperature;
    final tRange = tMax - tMin;
    final pRange = pMax - pMin;

    for (final s in measurement.samples) {
      final x = s.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      double y;
      if (tRange < 0.01) {
        y = (pMin + pMax) / 2;
      } else {
        y = pMin + (s.temperatureRounded - tMin) / tRange * pRange;
      }
      spots.add(FlSpot(x, y));
    }
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.15,
      color: Colors.orange,
      barWidth: 1.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      dashArray: [5, 4],
    );
  }

  // --- Axis helpers ---

  double _roundedMinY() {
    final minP = measurement.minPressure;
    final range = measurement.maxPressure - minP;
    final padding = max(range * 0.15, 0.5);
    final raw = minP - padding;
    final step = _niceInterval(range + 2 * padding);
    return (raw / step).floor() * step;
  }

  double _roundedMaxY() {
    final maxP = measurement.maxPressure;
    final range = maxP - measurement.minPressure;
    final padding = max(range * 0.15, 0.5);
    final raw = maxP + padding;
    final step = _niceInterval(range + 2 * padding);
    return (raw / step).ceil() * step;
  }

  /// Pick a "nice" interval that gives 4-8 grid lines.
  double _niceInterval(double range) {
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

  /// Time axis: pick an interval that gives ~5-8 labels.
  double _timeInterval(double totalSec) {
    const candidates = [
      30.0, 60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0, 7200.0, 14400.0, 21600.0,
    ];
    for (final c in candidates) {
      if (totalSec / c <= 10) return c;
    }
    return 21600.0;
  }

  Widget _timeLabel(double value, TitleMeta meta) {
    if (value == meta.max) return const SizedBox.shrink();
    final sec = value.toInt();
    String text;
    if (sec == 0) {
      text = '0';
    } else if (sec < 3600) {
      text = '${sec ~/ 60}min';
    } else {
      final h = sec ~/ 3600;
      final m = (sec % 3600) ~/ 60;
      text = m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
    }
    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _tempLabel(double value, TitleMeta meta, double pMin, double pMax) {
    if (value == meta.max || value == meta.min) return const SizedBox.shrink();
    final tMin = measurement.minTemperature;
    final tMax = measurement.maxTemperature;
    final tRange = tMax - tMin;
    final pRange = pMax - pMin;
    if (pRange < 0.001 || tRange < 0.01) return const SizedBox.shrink();
    final temp = tMin + (value - pMin) / pRange * tRange;
    return SideTitleWidget(
      meta: meta,
      child: Text('${temp.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 9)),
    );
  }

  int _closestIndex(int seconds) {
    if (measurement.samples.isEmpty) return -1;
    int best = 0;
    int bestD = 999999;
    for (int i = 0; i < measurement.samples.length; i++) {
      final d = (measurement.samples[i].timestamp.difference(measurement.startTime).inSeconds - seconds).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  // --- Legend ---

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(Colors.blue, 'Druck (bar)', false),
        const SizedBox(width: 24),
        _legendItem(Colors.orange, 'Temperatur (°C)', true),
      ],
    );
  }

  Widget _legendItem(Color color, String label, bool dashed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 3,
          child: dashed
              ? CustomPaint(painter: _DashedLinePainter(color))
              : Container(color: color),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 4, size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
