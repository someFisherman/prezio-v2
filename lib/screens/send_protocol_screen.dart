import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';

class SendProtocolScreen extends ConsumerStatefulWidget {
  final ProtocolData protocolData;

  const SendProtocolScreen({
    super.key,
    required this.protocolData,
  });

  @override
  ConsumerState<SendProtocolScreen> createState() => _SendProtocolScreenState();
}

class _SendProtocolScreenState extends ConsumerState<SendProtocolScreen> {
  bool _isProcessing = true;
  bool _localSaved = false;
  bool _cloudUploaded = false;
  String? _cloudError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateSaveAndUpload();
  }

  Future<void> _generateSaveAndUpload() async {
    setState(() {
      _isProcessing = true;
      _error = null;
      _cloudError = null;
    });

    try {
      final pdfGenerator = ref.read(pdfGeneratorProvider);
      final pdfPath = await pdfGenerator.generateProtocolPdf(widget.protocolData);

      final measurementService = ref.read(measurementServiceProvider);
      final csvContent = measurementService.exportToCsv(widget.protocolData.measurement);

      final storageService = ref.read(protocolStorageProvider);
      final localResult = await storageService.saveProtocol(
        pdfPath: pdfPath,
        csvContent: csvContent,
        protocolData: widget.protocolData,
      );

      setState(() => _localSaved = true);

      // Upload to Google Drive
      final driveService = ref.read(googleDriveServiceProvider);
      if (driveService.isSignedIn) {
        final folderName = localResult.folderPath.split('/').last.split('\\').last;
        final metadataJson = _buildMetadataJson(widget.protocolData, csvContent);

        final uploadResult = await driveService.uploadProtocol(
          folderName: folderName,
          pdfPath: pdfPath,
          csvContent: csvContent,
          metadataJson: metadataJson,
        );

        if (uploadResult.success) {
          setState(() => _cloudUploaded = true);
        } else {
          setState(() => _cloudError = uploadResult.error ?? 'Upload fehlgeschlagen');
        }
      } else {
        setState(() => _cloudError = 'Nicht mit Google angemeldet');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _buildMetadataJson(ProtocolData data, String csvContent) {
    final csvHash = sha256.convert(utf8.encode(csvContent)).toString();
    final meta = {
      'version': '2.0',
      'createdAt': DateTime.now().toIso8601String(),
      'object': data.objectName,
      'project': data.projectName,
      'author': data.author,
      'technician': data.technicianName,
      'measurement': {
        'filename': data.measurement.filename,
        'startTime': data.measurement.startTime.toIso8601String(),
        'endTime': data.measurement.endTime.toIso8601String(),
        'durationSeconds': data.measurement.duration.inSeconds,
        'sampleCount': data.measurement.samples.length,
      },
      'validation': {
        'nominalPressure': data.nominalPressure,
        'testMedium': data.testMedium.name,
        'testPressure': data.testPressure,
        'passed': data.passed,
        'result': data.result,
        'reason': data.validationReason,
      },
      'csvSha256': csvHash,
    };
    return const JsonEncoder.withIndent('  ').convert(meta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protokoll speichern'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildStatusCard(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.home),
              label: const Text('Zurueck zum Start'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.protocolData.passed ? Icons.check_circle : Icons.cancel,
                  color: widget.protocolData.passed ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Druckprotokoll',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.protocolData.passed
                            ? 'Pruefung bestanden'
                            : 'Pruefung nicht bestanden',
                        style: TextStyle(
                          color: widget.protocolData.passed ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildSummaryRow('Objekt', widget.protocolData.objectName),
            _buildSummaryRow('Projekt', widget.protocolData.projectName),
            _buildSummaryRow('Datum',
                Formatters.formatDate(widget.protocolData.measurement.startTime)),
            _buildSummaryRow('Monteur', widget.protocolData.technicianName),
            _buildSummaryRow('Pruefdruck',
                Formatters.formatPressureWithUnit(widget.protocolData.testPressure)),
            _buildSummaryRow('Dauer', widget.protocolData.testDuration),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Speicher-Status',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Row(
                children: [
                  SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Wird gespeichert und hochgeladen...'),
                ],
              )
            else if (_error != null)
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Fehler: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              )
            else ...[
              _buildStatusRow(
                icon: Icons.phone_iphone,
                label: 'Lokal gespeichert',
                success: _localSaved,
              ),
              const SizedBox(height: 8),
              _buildStatusRow(
                icon: Icons.cloud_upload,
                label: 'Google Drive',
                success: _cloudUploaded,
                error: _cloudError,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required bool success,
    String? error,
  }) {
    Color color;
    IconData statusIcon;
    String statusText;

    if (success) {
      color = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = label;
    } else if (error != null) {
      color = Colors.orange;
      statusIcon = Icons.warning;
      statusText = '$label - $error';
    } else {
      color = Colors.grey;
      statusIcon = Icons.hourglass_empty;
      statusText = '$label...';
    }

    return Row(
      children: [
        Icon(statusIcon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(statusText,
              style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
