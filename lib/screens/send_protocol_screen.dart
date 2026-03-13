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
  bool _isGenerating = false;
  bool _includeRawData = true;
  String? _pdfPath;
  String? _csvPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final pdfGenerator = ref.read(pdfGeneratorProvider);
      final pdfPath = await pdfGenerator.generateProtocolPdf(widget.protocolData);

      if (_includeRawData) {
        final measurementService = ref.read(measurementServiceProvider);
        final csvContent = measurementService.exportToCsv(widget.protocolData.measurement);
        final emailService = ref.read(emailServiceProvider);
        final csvPath = await emailService.saveCsvToTemp(
          csvContent,
          'messdaten_${widget.protocolData.measurement.filename}',
        );
        setState(() => _csvPath = csvPath);
      }

      setState(() => _pdfPath = pdfPath);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protokoll senden'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildOptionsCard(),
            const SizedBox(height: 24),
            _buildSendButton(),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.home),
              label: const Text('Zurück zum Start'),
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        widget.protocolData.passed ? 'Prüfung bestanden' : 'Prüfung nicht bestanden',
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
            _buildSummaryRow('Datum', Formatters.formatDate(widget.protocolData.measurement.startTime)),
            _buildSummaryRow('Monteur', widget.protocolData.technicianName),
            _buildSummaryRow('Prüfdruck', Formatters.formatPressureWithUnit(widget.protocolData.testPressure)),
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
              'PDF-Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            if (_isGenerating)
              const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('PDF wird erstellt...'),
                ],
              )
            else if (_error != null)
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Fehler: $_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              )
            else if (_pdfPath != null)
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('PDF erfolgreich erstellt'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anhänge',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: true,
              onChanged: null,
              title: const Text('Druckprotokoll (PDF)'),
              secondary: const Icon(Icons.picture_as_pdf, color: Colors.red),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _includeRawData,
              onChanged: (value) {
                setState(() => _includeRawData = value ?? false);
                if (value == true && _csvPath == null) {
                  _generatePdf();
                }
              },
              title: const Text('Rohdaten (CSV)'),
              secondary: const Icon(Icons.table_chart, color: Colors.green),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return ElevatedButton.icon(
      onPressed: (_pdfPath != null && !_isGenerating) ? _sendEmail : null,
      icon: const Icon(Icons.email),
      label: const Text('Per E-Mail senden'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Future<void> _sendEmail() async {
    if (_pdfPath == null) return;

    try {
      final emailService = ref.read(emailServiceProvider);
      await emailService.sendProtocol(
        pdfPath: _pdfPath!,
        csvPath: _includeRawData ? _csvPath : null,
        protocolData: widget.protocolData,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Öffnen der E-Mail-App: $e')),
        );
      }
    }
  }
}
