import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/models.dart';
import '../utils/formatters.dart';

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

  Future<String> generateProtocolPdf(ProtocolData data) async {
    final pdf = pw.Document();
    final logo = await _loadLehmannLogo();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(logo),
            pw.SizedBox(height: 30),
            _buildLocationDate(data),
            pw.SizedBox(height: 30),
            _buildTitle(),
            pw.SizedBox(height: 20),
            _buildProjectInfo(data),
            pw.SizedBox(height: 20),
            _buildIntroText(),
            pw.SizedBox(height: 20),
            _buildPressureInfo(data),
            pw.SizedBox(height: 20),
            _buildTestType(),
            pw.SizedBox(height: 30),
            _buildResult(data),
            pw.SizedBox(height: 30),
            if (data.chartImage != null) ...[
              _buildChartSection(data.chartImage!),
              pw.SizedBox(height: 30),
            ],
            _buildSignatureSection(data),
            pw.Spacer(),
            _buildFooter(),
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

  pw.Widget _buildHeader(pw.MemoryImage? logo) {
    if (logo != null) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Image(logo, width: 300, height: 90, fit: pw.BoxFit.contain),
        ],
      );
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'LEHMANN 2000',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red700,
              ),
            ),
            pw.Text(
              'Ihr Partner fuer Waermetechnik',
              style: pw.TextStyle(
                fontSize: 12,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildLocationDate(ProtocolData data) {
    final date = Formatters.formatDate(data.measurement.startTime);
    final locationText = data.location != null && data.location!.isNotEmpty
        ? data.location!.split(',').first.trim()
        : 'Zofingen';
    return pw.Text(
      '$locationText / $date',
      style: const pw.TextStyle(fontSize: 11, color: PdfColors.blue800),
    );
  }

  pw.Widget _buildTitle() {
    return pw.Text(
      'Druckprotokoll',
      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
    );
  }

  pw.Widget _buildProjectInfo(ProtocolData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildLabelValue('Objekt / Anlage:', data.objectName),
        pw.SizedBox(height: 8),
        _buildLabelValue('Projekt:', data.projectName),
        pw.SizedBox(height: 8),
        pw.Text(
          'Verfasser: ${data.author.isNotEmpty ? data.author : data.technicianName}',
          style: const pw.TextStyle(fontSize: 11),
        ),
        if (data.location != null && data.location!.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _buildLabelValue('Standort:', data.location!),
        ],
      ],
    );
  }

  pw.Widget _buildLabelValue(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(
            text: value.isNotEmpty ? value : '-',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildIntroText() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Sehr geehrte Damen und Herren', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 4),
        pw.Text('Anbei erhalten Sie unser Druckprotokoll', style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  pw.Widget _buildPressureInfo(ProtocolData data) {
    final testDuration = data.testDuration.isNotEmpty
        ? data.testDuration
        : Formatters.formatDuration(data.measurement.duration);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (data.testProfileName != null && data.testProfileName!.isNotEmpty)
          _buildInfoRow('Pruefprofil:', data.testProfileName!),
        _buildInfoRow('Betriebsdruck:', data.nominalPressure > 0 ? 'PN ${data.nominalPressure}' : '-'),
        _buildInfoRow('Druckpruefung:', data.testMedium.displayName),
        _buildInfoRow('Pruefdruck:', Formatters.formatPressureWithUnit(data.testPressure)),
        _buildInfoRow('Pruefdauer:', testDuration),
        if (data.detectedHoldDurationHours > 0)
          _buildInfoRow('Erkannte Haltezeit:', _formatPdfHours(data.detectedHoldDurationHours)),
        if (data.pressureDropBar > 0)
          _buildInfoRow('Druckabfall:', '${data.pressureDropBar.toStringAsFixed(3)} bar'),
      ],
    );
  }

  String _formatPdfHours(double hours) {
    if (hours < 1.0) {
      final mins = (hours * 60).round();
      return '${mins}min';
    }
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTestType() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text('Pruefart:', style: const pw.TextStyle(fontSize: 11)),
        ),
        pw.Text('Manometer', style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  pw.Widget _buildResult(ProtocolData data) {
    final resultText = data.passed ? 'OK' : 'Nicht OK';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Text(
              'Resultat:',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 70),
            pw.Text(
              resultText,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        if (data.failureReasons.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          ...data.failureReasons.map((r) => pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10, bottom: 2),
                child: pw.Text(
                  '- $r',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              )),
        ],
      ],
    );
  }

  pw.Widget _buildChartSection(Uint8List chartImage) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Druckverlauf:',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Image(pw.MemoryImage(chartImage), width: 400, height: 180),
        ),
      ],
    );
  }

  pw.Widget _buildSignatureSection(ProtocolData data) {
    final dateStr = data.signatureDate != null
        ? Formatters.formatDate(data.signatureDate!)
        : Formatters.formatDate(DateTime.now());

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Datum: $dateStr', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 20),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Links: Monteur (mit digitaler Unterschrift)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Monteur: ${data.technicianName}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 5),
                  if (data.signature != null)
                    pw.Image(pw.MemoryImage(data.signature!), width: 180, height: 70)
                  else
                    pw.Container(
                      width: 180,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                      ),
                      child: pw.SizedBox(height: 50),
                    ),
                ],
              ),
            ),
            pw.SizedBox(width: 40),
            // Rechts: Offenes Feld fuer Projektleiter / Auftraggeber
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Unterschrift:',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Container(
                    width: 180,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
                    ),
                    child: pw.SizedBox(height: 50),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Name:  ____________________________',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Column(
        children: [
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
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
          pw.SizedBox(height: 2),
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              children: [
                const pw.TextSpan(text: 'info@lehmann2000.ch '),
                pw.TextSpan(text: '|', style: pw.TextStyle(color: PdfColors.red700)),
                const pw.TextSpan(text: ' CHE-108.359.764 MWST'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
