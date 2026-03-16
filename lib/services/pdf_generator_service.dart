import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../utils/formatters.dart';
import '../utils/chart_data_helper.dart';

/// Ergebnis: zwei separate PDF-Pfade
class ProtocolPdfResult {
  final String protocolPath;
  final String chartPath;

  const ProtocolPdfResult({
    required this.protocolPath,
    required this.chartPath,
  });
}

class PdfGeneratorService {
  pw.MemoryImage? _lehmannLogo;

  Future<pw.MemoryImage?> _loadLehmannLogo() async {
    if (_lehmannLogo != null) return _lehmannLogo;
    try {
      final data = await rootBundle.load('assets/images/lehmann2000.png');
      _lehmannLogo = pw.MemoryImage(data.buffer.asUint8List());
      return _lehmannLogo;
    } catch (_) {
      return null;
    }
  }

  /// Erzeugt zwei separate PDFs: Protokoll (1 Seite) und Kurve (Querformat, eigene Seite)
  Future<ProtocolPdfResult> generateProtocolPdfs(ProtocolData data) async {
    final protocolPath = await _generateProtocolPdf(data);
    final chartPath = await _generateChartPdf(data.measurement);
    return ProtocolPdfResult(protocolPath: protocolPath, chartPath: chartPath);
  }

  /// PDF 1: Protokoll – kompakt auf 1 Seite
  Future<String> _generateProtocolPdf(ProtocolData data) async {
    final pdf = pw.Document();
    final logo = await _loadLehmannLogo();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeaderCompact(logo),
            pw.SizedBox(height: 8),
            _buildLocationDate(data),
            pw.SizedBox(height: 6),
            _buildTitleCompact(),
            pw.SizedBox(height: 8),
            _buildProjectInfoCompact(data),
            pw.SizedBox(height: 6),
            _buildIntroTextCompact(),
            pw.SizedBox(height: 6),
            _buildPressureInfoCompact(data),
            pw.SizedBox(height: 6),
            _buildTestTypeCompact(),
            pw.SizedBox(height: 8),
            _buildResultCompact(data),
            pw.SizedBox(height: 12),
            _buildSignatureSectionCompact(data),
            pw.Spacer(),
            _buildFooterCompact(),
          ],
        ),
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/druckprotokoll_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  /// PDF 2: Nur Kurve – Querformat, ganze Seite, aus Messdaten generiert
  Future<String> _generateChartPdf(Measurement measurement) async {
    if (measurement.samples.isEmpty) {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/druckkurve_$timestamp.pdf');
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => pw.Center(
            child: pw.Text(
              'Keine Messdaten vorhanden',
              style: pw.TextStyle(fontSize: 14),
            ),
          ),
        ),
      );
      await file.writeAsBytes(await pdf.save());
      return file.path;
    }

    final pMin = ChartDataHelper.roundedMinY(measurement);
    final pMax = ChartDataHelper.roundedMaxY(measurement);
    final totalSec = measurement.duration.inSeconds.toDouble();
    final pressureSpots = ChartDataHelper.smoothedPressureSpots(measurement);
    final tempSpots = ChartDataHelper.smoothedTempSpots(measurement, pMin, pMax);

    final xTicks = _computeTimeTicks(totalSec);
    final yTicks = _computePressureTicks(pMin, pMax);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(50),
        build: (context) => pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis(
              xTicks,
              format: (v) => _formatTimeLabel(v.toDouble()),
              divisions: true,
              divisionsColor: PdfColors.grey300,
            ),
            yAxis: pw.FixedAxis(
              yTicks,
              format: (v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1),
              divisions: true,
              divisionsColor: PdfColors.grey300,
            ),
          ),
          datasets: [
            pw.LineDataSet(
              data: pressureSpots.map((s) => pw.PointChartValue(s.x, s.y)).toList(),
              color: PdfColors.blue,
              lineWidth: 2.5,
              drawPoints: false,
              drawSurface: true,
              surfaceOpacity: 0.08,
              isCurved: true,
              smoothness: 0.4,
            ),
            pw.LineDataSet(
              data: tempSpots.map((s) => pw.PointChartValue(s.x, s.y)).toList(),
              color: PdfColors.orange,
              lineWidth: 1.5,
              drawPoints: false,
              lineColor: PdfColors.orange,
              isCurved: true,
              smoothness: 0.4,
            ),
          ],
        ),
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/druckkurve_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  List<double> _computeTimeTicks(double totalSec) {
    const candidates = [30.0, 60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0];
    double interval = 60;
    for (final c in candidates) {
      if (totalSec / c <= 12) {
        interval = c;
        break;
      }
    }
    final ticks = <double>[0];
    for (double t = interval; t < totalSec; t += interval) {
      ticks.add(t);
    }
    if (totalSec > 0 && (ticks.isEmpty || ticks.last < totalSec - 1)) {
      ticks.add(totalSec);
    }
    return ticks;
  }

  List<double> _computePressureTicks(double pMin, double pMax) {
    final range = pMax - pMin;
    final step = ChartDataHelper.niceInterval(range);
    final ticks = <double>[];
    for (double v = pMin; v <= pMax + 0.001; v += step) {
      ticks.add((v * 100).round() / 100);
    }
    return ticks.isEmpty ? [pMin, pMax] : ticks;
  }

  String _formatTimeLabel(double sec) {
    if (sec == 0) return '0';
    if (sec < 3600) return '${(sec / 60).round()}min';
    final h = (sec / 3600).floor();
    final m = ((sec % 3600) / 60).round();
    return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
  }

  pw.Widget _buildHeaderCompact(pw.MemoryImage? logo) {
    if (logo != null) {
      return pw.Image(logo, width: 280, height: 85, fit: pw.BoxFit.contain);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('LEHMANN 2000', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
        pw.Text('Ihr Partner fuer Waermetechnik', style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
      ],
    );
  }

  pw.Widget _buildLocationDate(ProtocolData data) {
    final now = DateTime.now();
    final locationText = data.location != null && data.location!.isNotEmpty
        ? data.location!.split(',').first.trim()
        : 'Zofingen';
    return pw.Text('$locationText / ${Formatters.formatDateTime(now)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800));
  }

  pw.Widget _buildTitleCompact() {
    return pw.Text('Druckprotokoll', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold));
  }

  pw.Widget _buildProjectInfoCompact(ProtocolData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildLabelValueCompact('Objekt:', data.objectName),
        _buildLabelValueCompact('Projekt:', data.projectName),
        pw.Text('Verfasser: ${data.author.isNotEmpty ? data.author : data.technicianName}', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildLabelValueCompact(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: value.isNotEmpty ? value : '-', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildIntroTextCompact() {
    return pw.Text('Sehr geehrte Damen und Herren, anbei erhalten Sie unser Druckprotokoll.', style: const pw.TextStyle(fontSize: 9));
  }

  pw.Widget _buildPressureInfoCompact(ProtocolData data) {
    final testDuration = data.testDuration.isNotEmpty ? data.testDuration : Formatters.formatDuration(data.measurement.duration);
    return pw.Wrap(
      runSpacing: 2,
      spacing: 16,
      children: [
        if (data.testProfileName != null && data.testProfileName!.isNotEmpty)
          pw.Text('Pruefprofil: ${data.testProfileName!}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Betriebsdruck: ${data.nominalPressure > 0 ? "PN ${data.nominalPressure}" : "-"}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Druckpruefung: ${data.testMedium.displayName}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Pruefdruck: ${Formatters.formatPressureWithUnit(data.testPressure)}', style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Pruefdauer: $testDuration', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  pw.Widget _buildTestTypeCompact() {
    return pw.Text('Pruefart: Manometer', style: const pw.TextStyle(fontSize: 9));
  }

  pw.Widget _buildResultCompact(ProtocolData data) {
    final resultText = data.passed ? 'OK' : 'Nicht OK';
    return pw.Row(
      children: [
        pw.Text('Resultat: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(resultText, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  pw.Widget _buildSignatureSectionCompact(ProtocolData data) {
    final techName = data.technicianName.isNotEmpty ? data.technicianName : (data.author.isNotEmpty ? data.author : 'Monteur');
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        _buildSignatureBlockCompact(hasSignature: data.signature != null, signature: data.signature, name: techName),
        pw.SizedBox(width: 32),
        _buildSignatureBlockCompact(hasSignature: false, signature: null, name: ''),
      ],
    );
  }

  pw.Widget _buildSignatureBlockCompact({required bool hasSignature, Uint8List? signature, required String name}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Unterschrift:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        if (hasSignature && signature != null)
          pw.Image(pw.MemoryImage(signature), width: 160, height: 55)
        else
          pw.Container(width: 160, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.SizedBox(height: 45)),
        pw.Text('Name: ${name.isNotEmpty ? name : "________________"}', style: const pw.TextStyle(fontSize: 8)),
      ],
    );
  }

  pw.Widget _buildFooterCompact() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Text('LEHMANN 2000 AG | Muellerweg 5 | 4800 Zofingen | +41 62 745 30 30 | info@lehmann2000.ch', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
    );
  }
}
