import 'dart:io';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class EmailService {
  Future<void> sendProtocol({
    required String pdfPath,
    String? csvPath,
    required ProtocolData protocolData,
    String? recipientEmail,
  }) async {
    final attachments = <String>[pdfPath];
    
    if (csvPath != null) {
      attachments.add(csvPath);
    }

    final subject = _buildSubject(protocolData);
    final body = _buildBody(protocolData);

    final email = Email(
      subject: subject,
      body: body,
      recipients: recipientEmail != null ? [recipientEmail] : [],
      attachmentPaths: attachments,
    );

    await FlutterEmailSender.send(email);
  }

  String _buildSubject(ProtocolData data) {
    final date = Formatters.formatDate(data.measurement.startTime);
    final result = data.passed ? 'Bestanden' : 'Nicht bestanden';
    
    if (data.objectName.isNotEmpty) {
      return 'Druckprotokoll - ${data.objectName} - $date - $result';
    }
    return 'Druckprotokoll - $date - $result';
  }

  String _buildBody(ProtocolData data) {
    final buffer = StringBuffer();
    
    buffer.writeln('Druckprotokoll');
    buffer.writeln('==============');
    buffer.writeln();
    
    if (data.objectName.isNotEmpty) {
      buffer.writeln('Objekt: ${data.objectName}');
    }
    if (data.projectName.isNotEmpty) {
      buffer.writeln('Projekt: ${data.projectName}');
    }
    
    buffer.writeln();
    buffer.writeln('Messung: ${data.measurement.filename}');
    buffer.writeln('Datum: ${Formatters.formatDateTime(data.measurement.startTime)}');
    buffer.writeln('Dauer: ${Formatters.formatDuration(data.measurement.duration)}');
    buffer.writeln();
    
    buffer.writeln('Prüfdruck: ${Formatters.formatPressureWithUnit(data.testPressure)}');
    buffer.writeln('Resultat: ${data.result}');
    buffer.writeln();
    
    buffer.writeln('Monteur: ${data.technicianName}');
    if (data.signatureDate != null) {
      buffer.writeln('Unterschrieben am: ${Formatters.formatDateTime(data.signatureDate!)}');
    }
    
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('Gesendet mit Prezio App');
    
    return buffer.toString();
  }

  Future<String> saveCsvToTemp(String csvContent, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(csvContent);
    return file.path;
  }
}
