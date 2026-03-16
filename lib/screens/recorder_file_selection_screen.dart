import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../utils/formatters.dart';
import 'internet_check_screen.dart';

class RecorderFileSelectionScreen extends ConsumerStatefulWidget {
  const RecorderFileSelectionScreen({super.key});

  @override
  ConsumerState<RecorderFileSelectionScreen> createState() =>
      _RecorderFileSelectionScreenState();
}

class _RecorderFileSelectionScreenState
    extends ConsumerState<RecorderFileSelectionScreen> {
  bool _isConnecting = true;
  bool _isLoading = false;
  String? _error;
  List<FileInfo> _files = [];
  String? _loadingFile;

  @override
  void initState() {
    super.initState();
    _connectAndLoadFiles();
  }

  Future<void> _connectAndLoadFiles() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final service = ref.read(measurementServiceProvider);
      final files = await service.listRecorderFiles();

      if (files.isEmpty) {
        final connected = await service.checkRecorderConnection();
        if (!connected) {
          setState(() {
            _error = 'Keine Verbindung zum Prezio Recorder.\n\n'
                'Bitte pruefen:\n'
                '- Ist der Recorder eingeschaltet?\n'
                '- Ist das Handy mit dem Recorder-WiFi verbunden?\n'
                '- Stimmt die IP-Adresse in den Einstellungen?';
          });
        } else {
          setState(() {
            _error = 'Verbindung OK, aber keine Messungen auf dem Recorder gefunden.';
          });
        }
      } else {
        files.sort((a, b) {
          if (a.modified == null && b.modified == null) return 0;
          if (a.modified == null) return 1;
          if (b.modified == null) return -1;
          return b.modified!.compareTo(a.modified!);
        });
        setState(() => _files = files);
      }
    } catch (e) {
      setState(() => _error = 'Verbindungsfehler: $e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  String _extractName(String filename) {
    final withoutExt = filename.replaceAll('.csv', '');
    // Format: messung_YYYY-MM-DD_HH-MM-SS_Name_Parts.csv
    final match = RegExp(r'^messung_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_(.+)$')
        .firstMatch(withoutExt);
    if (match != null) {
      return match.group(1)!.replaceAll('_', ' ');
    }
    // Fallback: alles nach dem 3. Underscore
    final parts = withoutExt.split('_');
    if (parts.length > 3) {
      return parts.sublist(3).join(' ');
    }
    return withoutExt;
  }

  Future<void> _loadAndNavigate(FileInfo file) async {
    setState(() {
      _isLoading = true;
      _loadingFile = file.filename;
    });

    try {
      final service = ref.read(measurementServiceProvider);
      final measurement = await service.loadSingleFromRecorder(file);

      if (measurement == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Messung konnte nicht geladen werden'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      ref.read(measurementsProvider.notifier).refresh();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InternetCheckScreen(measurement: measurement),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingFile = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messungen vom Recorder'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _connectAndLoadFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verbinde mit Prezio Recorder...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _connectAndLoadFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Messung antippen um Protokoll zu erstellen:',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              final name = _extractName(file.filename);
              final isThisLoading = _loadingFile == file.filename;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  onTap: _isLoading ? null : () => _loadAndNavigate(file),
                  leading: isThisLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.insert_drive_file, color: Colors.blue),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${(file.size / 1024).toStringAsFixed(1)} KB'
                    '${file.modified != null ? '  •  ${Formatters.formatDateTime(file.modified!)}' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
