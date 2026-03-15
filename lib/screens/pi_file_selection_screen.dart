import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../utils/formatters.dart';
import 'measurement_list_screen.dart';

class PiFileSelectionScreen extends ConsumerStatefulWidget {
  const PiFileSelectionScreen({super.key});

  @override
  ConsumerState<PiFileSelectionScreen> createState() => _PiFileSelectionScreenState();
}

class _PiFileSelectionScreenState extends ConsumerState<PiFileSelectionScreen> {
  bool _isConnecting = true;
  bool _isLoading = false;
  String? _error;
  List<FileInfo> _files = [];
  final Set<String> _selectedFiles = {};

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
      final files = await service.listPiFiles();

      if (files.isEmpty) {
        final connected = await service.checkPiConnection();
        if (!connected) {
          setState(() {
            _error = 'Keine Verbindung zum Raspberry Pi.\n\n'
                'Bitte pruefen:\n'
                '- Ist der Pi eingeschaltet?\n'
                '- Ist das Handy mit dem Pi-WiFi verbunden?\n'
                '- Stimmt die IP-Adresse in den Einstellungen?';
          });
        } else {
          setState(() {
            _error = 'Verbindung OK, aber keine Messungen auf dem Pi gefunden.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messungen vom Pi'),
        actions: [
          if (_files.isNotEmpty)
            TextButton.icon(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _selectedFiles.length == _files.length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              label: Text(
                _selectedFiles.length == _files.length ? 'Keine' : 'Alle',
              ),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _files.isNotEmpty && _selectedFiles.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadSelected,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isLoading
                        ? 'Wird geladen...'
                        : '${_selectedFiles.length} Messung(en) laden',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            )
          : null,
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
            Text('Verbinde mit Raspberry Pi...'),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFiles.contains(file.filename);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedFiles.add(file.filename);
                } else {
                  _selectedFiles.remove(file.filename);
                }
              });
            },
            title: Text(
              file.filename,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${(file.size / 1024).toStringAsFixed(1)} KB'
              '${file.modified != null ? ' - ${Formatters.formatDateTime(file.modified!)}' : ''}',
            ),
            secondary: const Icon(Icons.insert_drive_file, color: Colors.blue),
          ),
        );
      },
    );
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedFiles.length == _files.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles.addAll(_files.map((f) => f.filename));
      }
    });
  }

  Future<void> _loadSelected() async {
    setState(() => _isLoading = true);

    try {
      final service = ref.read(measurementServiceProvider);
      final selectedFileInfos = _files.where((f) => _selectedFiles.contains(f.filename)).toList();

      final count = await service.loadSelectedFromPi(selectedFileInfos);
      ref.read(measurementsProvider.notifier).refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count Messung(en) geladen')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MeasurementListScreen()),
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
        setState(() => _isLoading = false);
      }
    }
  }
}
