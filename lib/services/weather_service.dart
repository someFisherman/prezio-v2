import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double outdoorTempStart;
  final double outdoorTempEnd;
  final double maxTemp;
  final double minTemp;
  final double tempSwing;
  final bool fromApi;

  const WeatherData({
    required this.outdoorTempStart,
    required this.outdoorTempEnd,
    required this.maxTemp,
    required this.minTemp,
    required this.tempSwing,
    this.fromApi = true,
  });

  double get additionalTolerance {
    // Temperature swing beyond what the sensor captures creates uncertainty.
    // For air: ΔP/P ≈ ΔT/(T+273.15). A 10°C outdoor swing on a pipe
    // that is partially exposed can cause ~3% pressure variation.
    // We use half the outdoor swing as the "unaccounted" uncertainty.
    final unaccountedSwing = tempSwing * 0.5;
    if (unaccountedSwing < 2.0) return 0.0;
    return unaccountedSwing * 0.003;
  }
}

class WeatherService {
  Future<Position?> _getPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetch historical hourly temperatures for the measurement period.
  /// Uses Open-Meteo archive API (free, no key needed).
  Future<WeatherData?> fetchForPeriod(
    DateTime start,
    DateTime end,
  ) async {
    final position = await _getPosition();

    // Default to central Switzerland if GPS unavailable
    final lat = position?.latitude ?? 47.05;
    final lon = position?.longitude ?? 8.30;

    final startDate = _formatDate(start);
    final endDate = _formatDate(end);

    try {
      // Use forecast API for recent/today data, archive for older
      final now = DateTime.now();
      final daysDiff = now.difference(start).inDays;

      String url;
      if (daysDiff <= 7) {
        url = 'https://api.open-meteo.com/v1/forecast'
            '?latitude=$lat&longitude=$lon'
            '&hourly=temperature_2m'
            '&start_date=$startDate&end_date=$endDate'
            '&timezone=auto';
      } else {
        url = 'https://archive-api.open-meteo.com/v1/archive'
            '?latitude=$lat&longitude=$lon'
            '&hourly=temperature_2m'
            '&start_date=$startDate&end_date=$endDate'
            '&timezone=auto';
      }

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final hourly = data['hourly'];
      if (hourly == null) return null;

      final times = (hourly['time'] as List).cast<String>();
      final temps = (hourly['temperature_2m'] as List)
          .map((t) => (t as num?)?.toDouble())
          .toList();

      if (temps.isEmpty) return null;

      final validTemps = temps.whereType<double>().toList();
      if (validTemps.isEmpty) return null;

      // Find temps closest to measurement start/end
      double tempAtStart = validTemps.first;
      double tempAtEnd = validTemps.last;
      double minDiffStart = double.infinity;
      double minDiffEnd = double.infinity;

      for (int i = 0; i < times.length; i++) {
        if (temps[i] == null) continue;
        final t = DateTime.parse(times[i]);
        final diffStart = t.difference(start).inMinutes.abs().toDouble();
        final diffEnd = t.difference(end).inMinutes.abs().toDouble();

        if (diffStart < minDiffStart) {
          minDiffStart = diffStart;
          tempAtStart = temps[i]!;
        }
        if (diffEnd < minDiffEnd) {
          minDiffEnd = diffEnd;
          tempAtEnd = temps[i]!;
        }
      }

      final maxTemp = validTemps.reduce((a, b) => a > b ? a : b);
      final minTemp = validTemps.reduce((a, b) => a < b ? a : b);

      return WeatherData(
        outdoorTempStart: tempAtStart,
        outdoorTempEnd: tempAtEnd,
        maxTemp: maxTemp,
        minTemp: minTemp,
        tempSwing: maxTemp - minTemp,
      );
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
