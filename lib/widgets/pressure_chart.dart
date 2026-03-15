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
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: _calculatePressureInterval(),
        verticalInterval: _calculateTimeInterval(),
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1);
        },
        getDrawingVerticalLine: (value) {
          return FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: showTemperature
            ? AxisTitles(
                axisNameWidget: const Text('Temp (°C)', style: TextStyle(fontSize: 10)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 45,
                  interval: _calculateTempInterval(),
                  getTitlesWidget: _rightTitleWidget,
                ),
              )
            : const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text('Zeit'),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: _calculateTimeInterval(),
            getTitlesWidget: _bottomTitleWidget,
          ),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: const Text('Druck (bar)', style: TextStyle(fontSize: 10)),
          sideTitles: SideTitles(
            showTitles: true,
            interval: _calculatePressureInterval(),
            reservedSize: 50,
            getTitlesWidget: _leftTitleWidget,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
      ),
      minX: 0,
      maxX: measurement.duration.inSeconds.toDouble(),
      minY: _calculateMinY(),
      maxY: _calculateMaxY(),
      lineBarsData: [
        _buildPressureLine(),
        if (showTemperature) _buildTemperatureLine(),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final seconds = spot.x.toInt();
              final sampleIndex = _findClosestSampleIndex(seconds);
              if (sampleIndex < 0) return null;
              final sample = measurement.samples[sampleIndex];

              if (spot.barIndex == 0) {
                return LineTooltipItem(
                  '${Formatters.formatPressureWithUnit(sample.pressureRounded)}\n'
                  '${Formatters.formatTime(sample.timestamp)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              } else {
                return LineTooltipItem(
                  '${Formatters.formatTemperatureWithUnit(sample.temperatureRounded)}\n'
                  '${Formatters.formatTime(sample.timestamp)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              }
            }).toList();
          },
        ),
      ),
    );
  }

  int _findClosestSampleIndex(int seconds) {
    if (measurement.samples.isEmpty) return -1;
    int bestIndex = 0;
    int bestDiff = 999999;
    for (int i = 0; i < measurement.samples.length; i++) {
      final sampleSeconds = measurement.samples[i].timestamp.difference(measurement.startTime).inSeconds;
      final diff = (sampleSeconds - seconds).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  LineChartBarData _buildPressureLine() {
    final spots = <FlSpot>[];
    for (int i = 0; i < measurement.samples.length; i++) {
      final sample = measurement.samples[i];
      final x = sample.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      final y = double.parse(sample.pressureRounded.toStringAsFixed(2));
      spots.add(FlSpot(x, y));
    }

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: Colors.blue,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: spots.length < 50,
        getDotPainter: (spot, percent, bar, index) {
          return FlDotCirclePainter(
            radius: 3,
            color: Colors.blue,
            strokeWidth: 1,
            strokeColor: Colors.white,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        color: Colors.blue.withValues(alpha: 0.1),
      ),
    );
  }

  LineChartBarData _buildTemperatureLine() {
    final spots = <FlSpot>[];
    final pressureRange = _calculateMaxY() - _calculateMinY();
    final tempRange = measurement.maxTemperature - measurement.minTemperature;

    for (int i = 0; i < measurement.samples.length; i++) {
      final sample = measurement.samples[i];
      final x = sample.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      final tempRounded = double.parse(sample.temperatureRounded.toStringAsFixed(2));
      double mappedY;
      if (tempRange < 0.01) {
        mappedY = (_calculateMinY() + _calculateMaxY()) / 2;
      } else {
        mappedY = _calculateMinY() +
            (tempRounded - measurement.minTemperature) /
                tempRange *
                pressureRange;
      }
      spots.add(FlSpot(x, mappedY));
    }

    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      color: Colors.orange,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      dashArray: [5, 5],
    );
  }

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

  Widget _rightTitleWidget(double value, TitleMeta meta) {
    final pressureRange = _calculateMaxY() - _calculateMinY();
    final tempRange = measurement.maxTemperature - measurement.minTemperature;
    double temp;
    if (pressureRange < 0.001 || tempRange < 0.01) {
      temp = measurement.minTemperature;
    } else {
      temp = measurement.minTemperature +
          (value - _calculateMinY()) / pressureRange * tempRange;
    }
    return SideTitleWidget(
      meta: meta,
      child: Text(temp.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
    );
  }

  double _calculateMinY() {
    final min = measurement.minPressure;
    final padding = (measurement.maxPressure - min) * 0.1;
    return (min - padding).clamp(-1.0, double.infinity);
  }

  double _calculateMaxY() {
    final max = measurement.maxPressure;
    final padding = (max - measurement.minPressure) * 0.1;
    return max + padding;
  }

  double _calculatePressureInterval() {
    final range = _calculateMaxY() - _calculateMinY();
    if (range <= 0.1) return 0.01;
    if (range <= 0.5) return 0.05;
    if (range <= 1) return 0.1;
    if (range <= 5) return 0.5;
    return 1.0;
  }

  double _calculateTempInterval() {
    final tempRange = measurement.maxTemperature - measurement.minTemperature;
    final pressureRange = _calculateMaxY() - _calculateMinY();
    if (tempRange < 0.01 || pressureRange < 0.001) return 1.0;
    final pressureInterval = _calculatePressureInterval();
    return pressureInterval;
  }

  double _calculateTimeInterval() {
    final totalSeconds = measurement.duration.inSeconds;
    if (totalSeconds <= 60) return 10;
    if (totalSeconds <= 300) return 30;
    if (totalSeconds <= 600) return 60;
    if (totalSeconds <= 1800) return 300;
    if (totalSeconds <= 3600) return 600;
    return 1800;
  }

  Widget _bottomTitleWidget(double value, TitleMeta meta) {
    final seconds = value.toInt();
    String text;
    if (seconds < 60) {
      text = '${seconds}s';
    } else if (seconds < 3600) {
      text = '${seconds ~/ 60}m';
    } else {
      text = '${seconds ~/ 3600}h${(seconds % 3600) ~/ 60}m';
    }
    return SideTitleWidget(
      meta: meta,
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _leftTitleWidget(double value, TitleMeta meta) {
    return SideTitleWidget(
      meta: meta,
      child: Text(Formatters.formatPressure(value), style: const TextStyle(fontSize: 10)),
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
