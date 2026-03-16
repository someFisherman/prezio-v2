import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'send_protocol_screen.dart';

class SignatureScreen extends ConsumerStatefulWidget {
  final ProtocolData protocolData;

  const SignatureScreen({
    super.key,
    required this.protocolData,
  });

  @override
  ConsumerState<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends ConsumerState<SignatureScreen> {
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final ScrollController _scrollController = ScrollController();
  bool _isFullScreen = false;
  bool _isFinalizing = false;

  @override
  void initState() {
    super.initState();
    _signatureController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenSignature();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unterschrift'),
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildChartPreview(),
            const SizedBox(height: 16),
            _buildSignatureCard(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: (_signatureController.isNotEmpty && !_isFinalizing)
                  ? _finalize
                  : null,
              icon: _isFinalizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isFinalizing ? 'Wird erstellt...' : 'Protokoll erstellen & speichern'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartPreview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Druckverlauf (wird als separates PDF gespeichert)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 400,
              height: 300,
              child: PressureChart(
                measurement: widget.protocolData.measurement,
                height: 300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Unterschrift',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _isFullScreen = true),
                      icon: const Icon(Icons.fullscreen),
                      tooltip: 'Vollbild',
                    ),
                    IconButton(
                      onPressed: () {
                        _signatureController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: 'Löschen',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Monteur: ${widget.protocolData.technicianName}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Signature(
                  controller: _signatureController,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bitte hier unterschreiben. Für Vollbild auf das Icon tippen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullScreenSignature() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Signature(
              controller: _signatureController,
              backgroundColor: Colors.white,
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Unterschrift: ${widget.protocolData.technicianName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[400],
                        ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          _signatureController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        tooltip: 'Löschen',
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _isFullScreen = false),
                        icon: const Icon(Icons.check),
                        label: const Text('Fertig'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalize() async {
    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte unterschreiben')),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      Uint8List? signatureBytes;
      try {
        signatureBytes = await _signatureController.toPngBytes(
          height: 400,
          width: 800,
        );
      } catch (_) {}
      signatureBytes ??= await _signatureController.toPngBytes();

      final updatedProtocol = widget.protocolData.copyWith(
        signature: signatureBytes,
        signatureDate: DateTime.now(),
      );

      ref.read(protocolDataProvider.notifier).state = updatedProtocol;

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SendProtocolScreen(protocolData: updatedProtocol),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFinalizing = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

}
