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
  String? _error;
  String? _savedPath;
  bool _cloudUploaded = false;
  String? _cloudError;

  @override
  void initState() {
    super.initState();
    _generateAndSave();
  }

  Future<void> _generateAndSave() async {
    setState(() {
      _isProcessing = true;
      _error = null;
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

      final localFolder = localResult.folderPath.split('/').last.split('\\').last;
      final folderName = '${localFolder}_${DateTime.now().millisecondsSinceEpoch}';
      setState(() => _savedPath = localResult.folderPath);

      final supabaseService = ref.read(supabaseUploadServiceProvider);
      if (supabaseService.isConfigured) {
        final uploadResult = await supabaseService.uploadProtocol(
          pdfPath: pdfPath,
          csvContent: csvContent,
          protocolData: widget.protocolData,
          folderName: folderName,
        );
        if (mounted) {
          setState(() {
            _cloudUploaded = uploadResult.success;
            _cloudError = uploadResult.error;
          });
        }
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
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
            if (widget.protocolData.location != null &&
                widget.protocolData.location!.isNotEmpty)
              _buildSummaryRow('Standort', widget.protocolData.location!),
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
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
                  Text('Wird gespeichert...'),
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
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lokal gespeichert',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _cloudUploaded ? Icons.cloud_done : Icons.cloud_off,
                    color: _cloudUploaded
                        ? Colors.green
                        : (_cloudError != null ? Colors.orange : Colors.grey),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _cloudUploaded
                          ? 'Cloud hochgeladen'
                          : (_cloudError ?? 'Cloud nicht konfiguriert'),
                      style: TextStyle(
                        color: _cloudUploaded ? Colors.green : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (_savedPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  _savedPath!,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
