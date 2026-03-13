import 'package:intl/intl.dart';

class Formatters {
  static final _pressureFormat = NumberFormat('0.00', 'de_CH');
  static final _temperatureFormat = NumberFormat('0.0', 'de_CH');
  static final _dateFormat = DateFormat('dd.MM.yyyy', 'de_CH');
  static final _timeFormat = DateFormat('HH:mm:ss', 'de_CH');
  static final _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm', 'de_CH');

  static String formatPressure(double value) {
    return _pressureFormat.format(value);
  }

  static String formatPressureWithUnit(double value) {
    return '${formatPressure(value)} bar';
  }

  static String formatTemperature(double value) {
    return _temperatureFormat.format(value);
  }

  static String formatTemperatureWithUnit(double value) {
    return '${formatTemperature(value)} °C';
  }

  static String formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  static String formatTime(DateTime date) {
    return _timeFormat.format(date);
  }

  static String formatDateTime(DateTime date) {
    return _dateTimeFormat.format(date);
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}min';
    } else if (minutes > 0) {
      return '${minutes}min ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  static double roundPressure(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  static double roundTemperature(double value) {
    return (value * 100).roundToDouble() / 100;
  }
}
