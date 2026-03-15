import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';

class CsvParserService {
  static const _uuid = Uuid();

  Measurement? parseFromString(String csvContent, {String filename = 'unknown.csv'}) {
    try {
      final metadata = _parseMetadataHeaders(csvContent);
      final csvWithoutComments = _stripCommentLines(csvContent);

      final lines = const CsvToListConverter(
        fieldDelimiter: ',',
        eol: '\n',
      ).convert(csvWithoutComments);

      if (lines.length < 2) {
        return null;
      }

      final headerRow = lines[0];
      if (!_isValidHeader(headerRow)) {
        return null;
      }

      final samples = <Sample>[];
      for (int i = 1; i < lines.length; i++) {
        final row = lines[i];
        if (row.length >= 7) {
          try {
            samples.add(Sample.fromCsvRow(row));
          } catch (e) {
            continue;
          }
        }
      }

      if (samples.isEmpty) {
        return null;
      }

      final startTime = samples.first.timestamp;
      final endTime = samples.last.timestamp;
      final duration = endTime.difference(startTime);

      return Measurement(
        id: _uuid.v4(),
        filename: filename,
        startTime: startTime,
        endTime: endTime,
        duration: duration,
        samples: samples,
        validationStatus: ValidationStatus.pending,
        metadata: metadata,
      );
    } catch (e) {
      return null;
    }
  }

  CsvMetadata? _parseMetadataHeaders(String csvContent) {
    String? name;
    int? pn;
    String? medium;
    double? intervalS;
    bool foundAny = false;

    for (final line in csvContent.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#')) break;

      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;

      final key = trimmed.substring(1, colonIdx).trim().toLowerCase();
      final value = trimmed.substring(colonIdx + 1).trim();

      switch (key) {
        case 'name':
          name = value;
          foundAny = true;
        case 'pn':
          pn = int.tryParse(value);
          foundAny = true;
        case 'medium':
          medium = value;
          foundAny = true;
        case 'interval':
          intervalS = double.tryParse(value);
          foundAny = true;
      }
    }

    return foundAny ? CsvMetadata(name: name, pn: pn, medium: medium, intervalS: intervalS) : null;
  }

  String _stripCommentLines(String csvContent) {
    final lines = csvContent.split('\n');
    final dataLines = lines.where((l) => !l.trimLeft().startsWith('#'));
    return dataLines.join('\n');
  }

  bool _isValidHeader(List<dynamic> header) {
    if (header.length < 7) return false;
    
    final headerStr = header.map((e) => e.toString().toLowerCase()).toList();
    
    return headerStr[0].contains('no') &&
        headerStr[1].contains('datetime') &&
        headerStr[3].contains('p1') &&
        headerStr[4].contains('tob1');
  }

  String generateCsvFromMeasurement(Measurement measurement) {
    final rows = <List<dynamic>>[];
    
    rows.add([
      'No',
      'Datetime [local time]',
      'Datetime [UTC]',
      'P1 [bar]',
      'TOB1 [°C]',
      'P1 rounded [bar]',
      'TOB1 rounded [°C]',
    ]);

    for (final sample in measurement.samples) {
      rows.add([
        sample.index,
        _formatLocalDateTime(sample.timestamp),
        sample.timestampUtc.toIso8601String(),
        sample.pressureBar,
        sample.temperatureC,
        sample.pressureRounded,
        sample.temperatureRounded,
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  String _formatLocalDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
