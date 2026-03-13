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
    this.showTemperature = false,
    this.height = 250,
  });

  @override
  Widget build(BuildContext context) {
    if (measurement.samples.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Keine Messdaten vorhanden'),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: _calculatePressureInterval(),
            verticalInterval: _calculateTimeInterval(),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.2),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
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
              axisNameWidget: const Text('Druck (bar)'),
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
            border: Border.all(color: Colors.grey.withOpacity(0.5)),
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
                  final index = spot.x.toInt();
                  if (index >= 0 && index < measurement.samples.length) {
                    final sample = measurement.samples[index];
                    return LineTooltipItem(
                      '${Formatters.formatPressureWithUnit(sample.pressureRounded)}\n${Formatters.formatTime(sample.timestamp)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                  return null;
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildPressureLine() {
    final spots = <FlSpot>[];
    
    for (int i = 0; i < measurement.samples.length; i++) {
      final sample = measurement.samples[i];
      final x = sample.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      spots.add(FlSpot(x, sample.pressureRounded));
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
        color: Colors.blue.withOpacity(0.1),
      ),
    );
  }

  LineChartBarData _buildTemperatureLine() {
    final spots = <FlSpot>[];
    
    for (int i = 0; i < measurement.samples.length; i++) {
      final sample = measurement.samples[i];
      final x = sample.timestamp.difference(measurement.startTime).inSeconds.toDouble();
      final normalizedTemp = (sample.temperatureRounded - measurement.minTemperature) / 
          (measurement.maxTemperature - measurement.minTemperature) *
          (measurement.maxPressure - measurement.minPressure) + measurement.minPressure;
      spots.add(FlSpot(x, normalizedTemp));
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
      child: Text(
        text,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }

  Widget _leftTitleWidget(double value, TitleMeta meta) {
    return SideTitleWidget(
      meta: meta,
      child: Text(
        Formatters.formatPressure(value),
        style: const TextStyle(fontSize: 10),
      ),
    );
  }
}
