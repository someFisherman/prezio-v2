import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/models.dart';
import '../utils/formatters.dart';

class PdfGeneratorService {
  Future<String> generateProtocolPdf(ProtocolData data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(50),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildHeader(data),
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
            _buildTestTypes(data),
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

  pw.Widget _buildHeader(ProtocolData data) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'SOLECO',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red700,
              ),
            ),
            pw.Text(
              'Ihr Partner für Wärmetechnik',
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
    return pw.Text(
      'Zofingen / $date',
      style: const pw.TextStyle(
        fontSize: 11,
        color: PdfColors.blue800,
      ),
    );
  }

  pw.Widget _buildTitle() {
    return pw.Text(
      'Druckprotokoll',
      style: pw.TextStyle(
        fontSize: 22,
        fontWeight: pw.FontWeight.bold,
      ),
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
      ],
    );
  }

  pw.Widget _buildLabelValue(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label ',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
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
        pw.Text(
          'Sehr geehrte Damen und Herren',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Anbei erhalten Sie unser Druckprotokoll',
          style: const pw.TextStyle(fontSize: 11),
        ),
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
        _buildInfoRow('Betriebsdruck:', 
            data.nominalPressure > 0 ? 'PN ${data.nominalPressure}' : '-'),
        _buildInfoRow('Druckprüfung:', data.testMedium.displayName),
        _buildInfoRow('Prüfdruck:', Formatters.formatPressureWithUnit(data.testPressure)),
        _buildInfoRow('Prüfdauer:', testDuration),
      ],
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTestTypes(ProtocolData data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                'Prüfart:',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildTestTypeItem('optisch', data.testTypes.contains(TestType.optical)),
                pw.SizedBox(height: 6),
                _buildTestTypeItem('Lecksuchspray', data.testTypes.contains(TestType.leakSpray)),
                pw.SizedBox(height: 6),
                _buildTestTypeItem('Röntgenprüfung', data.testTypes.contains(TestType.xray)),
                pw.SizedBox(height: 6),
                _buildTestTypeItem('Vakuumtest', data.testTypes.contains(TestType.vacuum)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildTestTypeItem(String label, bool selected) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          margin: const pw.EdgeInsets.only(right: 8),
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            color: selected ? PdfColors.black : PdfColors.white,
            border: pw.Border.all(color: PdfColors.black, width: 0.5),
          ),
        ),
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  pw.Widget _buildResult(ProtocolData data) {
    final resultText = data.result.isNotEmpty 
        ? data.result 
        : (data.passed ? 'OK' : 'Nicht OK');

    return pw.Row(
      children: [
        pw.Text(
          'Resultat:',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(width: 70),
        pw.Text(
          resultText,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildChartSection(Uint8List chartImage) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Druckverlauf:',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Center(
          child: pw.Image(
            pw.MemoryImage(chartImage),
            width: 400,
            height: 180,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildSignatureSection(ProtocolData data) {
    final dateStr = data.signatureDate != null
        ? Formatters.formatDate(data.signatureDate!)
        : Formatters.formatDate(DateTime.now());

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Datum $dateStr, Unterschrift',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 5),
            if (data.signature != null)
              pw.Image(
                pw.MemoryImage(data.signature!),
                width: 150,
                height: 50,
              )
            else
              pw.Container(
                width: 200,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.black, width: 0.5),
                  ),
                ),
                child: pw.SizedBox(height: 40),
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
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                children: [
                  const pw.TextSpan(text: 'SOLECO AG '),
                  pw.TextSpan(
                    text: '|',
                    style: pw.TextStyle(color: PdfColors.red700),
                  ),
                  const pw.TextSpan(text: ' Adresse '),
                  pw.TextSpan(
                    text: '|',
                    style: pw.TextStyle(color: PdfColors.red700),
                  ),
                  const pw.TextSpan(text: ' PLZ Ort '),
                  pw.TextSpan(
                    text: '|',
                    style: pw.TextStyle(color: PdfColors.red700),
                  ),
                  const pw.TextSpan(text: ' info@soleco.ch'),
                ],
              ),
            ),
          ),
          pw.Text(
            'Seite 1',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }
}
