class Sample {
  final int index;
  final DateTime timestamp;
  final DateTime timestampUtc;
  final double pressureBar;
  final double temperatureC;
  final double pressureRounded;
  final double temperatureRounded;

  const Sample({
    required this.index,
    required this.timestamp,
    required this.timestampUtc,
    required this.pressureBar,
    required this.temperatureC,
    required this.pressureRounded,
    required this.temperatureRounded,
  });

  factory Sample.fromCsvRow(List<dynamic> row) {
    return Sample(
      index: int.tryParse(row[0].toString()) ?? 0,
      timestamp: _parseLocalDateTime(row[1].toString()),
      timestampUtc: DateTime.tryParse(row[2].toString()) ?? DateTime.now(),
      pressureBar: double.tryParse(row[3].toString()) ?? 0.0,
      temperatureC: double.tryParse(row[4].toString()) ?? 0.0,
      pressureRounded: double.tryParse(row[5].toString()) ?? 0.0,
      temperatureRounded: double.tryParse(row[6].toString()) ?? 0.0,
    );
  }

  static DateTime _parseLocalDateTime(String dateStr) {
    try {
      final parts = dateStr.split(' ');
      if (parts.length != 2) return DateTime.now();

      final dateParts = parts[0].split('.');
      final timeParts = parts[1].split(':');

      if (dateParts.length != 3 || timeParts.length != 3) return DateTime.now();

      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[1]),
        int.parse(dateParts[0]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (e) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'timestamp': timestamp.toIso8601String(),
        'timestampUtc': timestampUtc.toIso8601String(),
        'pressureBar': pressureBar,
        'temperatureC': temperatureC,
        'pressureRounded': pressureRounded,
        'temperatureRounded': temperatureRounded,
      };
}
