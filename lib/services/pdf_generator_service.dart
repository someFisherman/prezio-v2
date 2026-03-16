import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../utils/formatters.dart';
import '../utils/chart_data_helper.dart';

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

  Future<ProtocolPdfResult> generateProtocolPdfs(ProtocolData data) async {
    final logo = await _loadLehmannLogo();
    final protocolPath = await _generateProtocolPdf(data, logo);
    final chartPath = await _generateChartPdf(data, logo);
    return ProtocolPdfResult(protocolPath: protocolPath, chartPath: chartPath);
  }

  // =========================================================================
  // PDF 1: Protokoll – kompakt, 1 Seite
  // =========================================================================

  Future<String> _generateProtocolPdf(ProtocolData data, pw.MemoryImage? logo) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(logo),
            pw.SizedBox(height: 14),
            _buildLocationDate(data),
            pw.SizedBox(height: 10),
            pw.Text('Druckprotokoll', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
            _buildProjectInfo(data),
            pw.SizedBox(height: 10),
            pw.Text('Sehr geehrte Damen und Herren, anbei erhalten Sie unser Druckprotokoll.', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
            _buildPressureTable(data),
            pw.SizedBox(height: 10),
            _buildResult(data),
            pw.SizedBox(height: 24),
            _buildSignatureSection(data),
            pw.Spacer(),
            _buildFooter(),
          ],
        ),
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/druckprotokoll_$ts.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // =========================================================================
  // PDF 2: Druckkurve – Querformat, ganze Seite, mit Beschriftungen
  // =========================================================================

  Future<String> _generateChartPdf(ProtocolData data, pw.MemoryImage? logo) async {
    final measurement = data.measurement;
    final pdf = pw.Document();

    if (measurement.samples.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) => pw.Center(
            child: pw.Text('Keine Messdaten vorhanden', style: pw.TextStyle(fontSize: 14)),
          ),
        ),
      );
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/druckkurve_$ts.pdf');
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

    final tMin = measurement.minTemperature;
    final tMax = measurement.maxTemperature;

    final dateStr = Formatters.formatDateTime(measurement.startTime);
    final objectName = data.objectName.isNotEmpty ? data.objectName : '-';
    final projectName = data.projectName.isNotEmpty ? data.projectName : '-';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.only(left: 40, right: 40, top: 24, bottom: 24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Kopfzeile: Logo + Bezugsdaten
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Image(logo, width: 180, height: 50, fit: pw.BoxFit.contain),
                if (logo != null)
                  pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Druckverlauf', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 2),
                      pw.Text('Objekt: $objectName  |  Projekt: $projectName  |  $dateStr', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            // Achsenbeschriftungen links (bar) und unten (Zeit)
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Y-Achse Label
                  pw.Transform.rotateBox(
                    angle: -3.14159 / 2,
                    child: pw.Text('Druck (bar)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blue)),
                  ),
                  pw.SizedBox(width: 4),
                  // Chart
                  pw.Expanded(
                    child: pw.Chart(
                      grid: pw.CartesianGrid(
                        xAxis: pw.FixedAxis(
                          xTicks,
                          format: (v) => _formatTimeLabel(v.toDouble()),
                          divisions: true,
                          divisionsColor: PdfColors.grey300,
                          textStyle: const pw.TextStyle(fontSize: 7),
                        ),
                        yAxis: pw.FixedAxis(
                          yTicks,
                          format: (v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1),
                          divisions: true,
                          divisionsColor: PdfColors.grey300,
                          textStyle: const pw.TextStyle(fontSize: 7),
                        ),
                      ),
                      overlay: pw.ChartLegend(
                        position: pw.Alignment.topRight,
                        direction: pw.Axis.horizontal,
                      ),
                      datasets: [
                        pw.LineDataSet(
                          legend: 'Druck (bar)',
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
                          legend: 'Temperatur (${tMin.toStringAsFixed(1)} - ${tMax.toStringAsFixed(1)} °C)',
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
                ],
              ),
            ),
            // X-Achse Label
            pw.Center(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text('Zeit', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              ),
            ),
          ],
        ),
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}/druckkurve_$ts.pdf');
    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  List<double> _computeTimeTicks(double totalSec) {
    const candidates = [30.0, 60.0, 120.0, 300.0, 600.0, 900.0, 1800.0, 3600.0, 7200.0];
    double interval = 3600;
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

  // ---- Protokoll-Widgets ----

  pw.Widget _buildHeader(pw.MemoryImage? logo) {
    if (logo != null) {
      return pw.Image(logo, width: 420, height: 130, fit: pw.BoxFit.contain);
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('LEHMANN 2000', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
        pw.Text('Ihr Partner fuer Waermetechnik', style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
      ],
    );
  }

  pw.Widget _buildLocationDate(ProtocolData data) {
    final now = DateTime.now();
    final locationText = data.location != null && data.location!.isNotEmpty
        ? data.location!.split(',').first.trim()
        : 'Zofingen';
    return pw.Text('$locationText / ${Formatters.formatDateTime(now)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.blue800));
  }

  pw.Widget _buildProjectInfo(ProtocolData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _labelValue('Objekt / Anlage:', data.objectName),
        pw.SizedBox(height: 3),
        _labelValue('Projekt:', data.projectName),
        pw.SizedBox(height: 3),
        pw.Text('Verfasser: ${data.author.isNotEmpty ? data.author : data.technicianName}', style: const pw.TextStyle(fontSize: 10)),
        if (data.location != null && data.location!.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          _labelValue('Standort:', data.location!),
        ],
      ],
    );
  }

  pw.Widget _labelValue(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(children: [
        pw.TextSpan(text: '$label ', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.TextSpan(text: value.isNotEmpty ? value : '-', style: const pw.TextStyle(fontSize: 10)),
      ]),
    );
  }

  pw.Widget _buildPressureTable(ProtocolData data) {
    final testDuration = data.testDuration.isNotEmpty ? data.testDuration : Formatters.formatDuration(data.measurement.duration);
    final rows = <List<String>>[
      if (data.testProfileName != null && data.testProfileName!.isNotEmpty)
        ['Pruefprofil', data.testProfileName!],
      ['Betriebsdruck', data.nominalPressure > 0 ? 'PN ${data.nominalPressure}' : '-'],
      ['Druckpruefung', data.testMedium.displayName],
      ['Pruefdruck', Formatters.formatPressureWithUnit(data.testPressure)],
      ['Pruefdauer', testDuration],
      if (data.detectedHoldDurationHours > 0)
        ['Erkannte Haltezeit', _formatPdfHours(data.detectedHoldDurationHours)],
      if (data.pressureDropBar > 0)
        ['Druckabfall', '${data.pressureDropBar.toStringAsFixed(3)} bar'],
      ['Pruefart', 'Manometer'],
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(130),
        1: const pw.FlexColumnWidth(),
      },
      children: rows.map((r) => pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(r[0], style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(r[1], style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      )).toList(),
    );
  }

  String _formatPdfHours(double hours) {
    if (hours < 1.0) return '${(hours * 60).round()}min';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  pw.Widget _buildResult(ProtocolData data) {
    final resultText = data.passed ? 'OK' : 'Nicht OK';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Text('Resultat: ', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(resultText, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: data.passed ? PdfColors.green800 : PdfColors.red)),
        ]),
        if (data.failureReasons.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          ...data.failureReasons.map((r) => pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 1),
            child: pw.Text('- $r', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          )),
        ],
      ],
    );
  }

  pw.Widget _buildSignatureSection(ProtocolData data) {
    final techName = data.technicianName.isNotEmpty ? data.technicianName : (data.author.isNotEmpty ? data.author : 'Monteur');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Datum: ${Formatters.formatDateTime(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _signatureBlock(hasSignature: data.signature != null, signature: data.signature, name: techName),
            pw.SizedBox(width: 36),
            _signatureBlock(hasSignature: false, signature: null, name: ''),
          ],
        ),
      ],
    );
  }

  pw.Widget _signatureBlock({required bool hasSignature, Uint8List? signature, required String name}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Unterschrift:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          if (hasSignature && signature != null)
            pw.Image(pw.MemoryImage(signature), width: 180, height: 60)
          else
            pw.Container(width: 180, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5))), child: pw.SizedBox(height: 50)),
          pw.SizedBox(height: 3),
          pw.Text('Name: ${name.isNotEmpty ? name : "____________________________"}', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              children: [
                const pw.TextSpan(text: 'LEHMANN 2000 AG '),
                pw.TextSpan(text: '|', style: pw.TextStyle(color: PdfColors.red700)),
                const pw.TextSpan(text: ' Muellerweg 5 '),
                pw.TextSpan(text: '|', style: pw.TextStyle(color: PdfColors.red700)),
                const pw.TextSpan(text: ' 4800 Zofingen '),
                pw.TextSpan(text: '|', style: pw.TextStyle(color: PdfColors.red700)),
                const pw.TextSpan(text: ' +41 62 745 30 30'),
              ],
            ),
          ),
          pw.Text('info@lehmann2000.ch', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      ),
    );
  }
}
