import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/services.dart';

class PiRecordingScreen extends ConsumerStatefulWidget {
  const PiRecordingScreen({super.key});

  @override
  ConsumerState<PiRecordingScreen> createState() => _PiRecordingScreenState();
}

class _PiRecordingScreenState extends ConsumerState<PiRecordingScreen> {
  final _nameController = TextEditingController(text: 'Messung');
  final _intervalController = TextEditingController(text: '10');
  int _selectedPN = 25;
  String _selectedMedium = 'air';

  bool _isConnecting = true;
  bool _isStarting = false;
  bool _isStopping = false;
  HealthStatus? _health;
  RecordingStatus? _recordingStatus;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _nameController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final service = ref.read(measurementServiceProvider);
      final health = await service.piConnection.getHealth();

      if (health == null) {
        setState(() {
          _error = 'Keine Verbindung zum Raspberry Pi.\n\n'
              'Bitte pruefen:\n'
              '- Ist der Pi eingeschaltet?\n'
              '- Ist das Handy mit dem Pi-WiFi verbunden?\n'
              '- Stimmt die IP-Adresse in den Einstellungen?';
        });
      } else {
        setState(() => _health = health);
        await _fetchRecordingStatus();
        _startPolling();
      }
    } catch (e) {
      setState(() => _error = 'Verbindungsfehler: $e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchRecordingStatus();
    });
  }

  Future<void> _fetchRecordingStatus() async {
    final service = ref.read(measurementServiceProvider);
    final status = await service.piConnection.getRecordingStatus();
    if (mounted && status != null) {
      setState(() => _recordingStatus = status);
    }
  }

  Future<void> _startRecording() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Namen eingeben')),
      );
      return;
    }

    final interval = double.tryParse(_intervalController.text.trim());
    if (interval == null || interval < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Intervall muss mindestens 1 Sekunde sein')),
      );
      return;
    }

    setState(() => _isStarting = true);

    try {
      final service = ref.read(measurementServiceProvider);
      final result = await service.piConnection.startRecording(
        name: name,
        pn: _selectedPN,
        medium: _selectedMedium,
        intervalS: interval,
      );

      if (result.containsKey('error')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        await _fetchRecordingStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aufzeichnung gestartet')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _isStopping = true);

    try {
      final service = ref.read(measurementServiceProvider);
      final result = await service.piConnection.stopRecording();

      if (result.containsKey('error')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        await _fetchRecordingStatus();
        if (mounted) {
          final samples = result['samples'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aufzeichnung gestoppt ($samples Messpunkte)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufzeichnung'),
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
                onPressed: _checkConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final isRecording = _recordingStatus?.isRecording ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionCard(),
          const SizedBox(height: 16),
          if (isRecording)
            _buildActiveRecordingCard()
          else
            _buildNewRecordingCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    final sensorOk = _health?.sensorConnected ?? false;
    final sn = _health?.serialNumber ?? '-';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verbindung',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.wifi, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                const Text('Raspberry Pi verbunden'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  sensorOk ? Icons.sensors : Icons.sensors_off,
                  color: sensorOk ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(sensorOk
                    ? 'Drucksensor verbunden (SN: $sn)'
                    : 'Kein Drucksensor erkannt'),
              ],
            ),
            if (_recordingStatus?.lastP1 != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.speed, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Aktuell: ${_recordingStatus!.lastP1!.toStringAsFixed(2)} bar / '
                    '${_recordingStatus!.lastTob1?.toStringAsFixed(1) ?? "-"} °C',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveRecordingCard() {
    final s = _recordingStatus!;

    return Card(
      color: Colors.green.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Aufzeichnung laeuft',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Name', s.name ?? '-'),
            _buildInfoRow('PN', 'PN ${s.pn ?? "-"}'),
            _buildInfoRow('Medium', s.medium == 'air' ? 'Luft' : 'Wasser'),
            _buildInfoRow('Intervall', '${s.intervalS?.toStringAsFixed(0) ?? "-"}s'),
            _buildInfoRow('Laufzeit', s.elapsedFormatted),
            _buildInfoRow('Messpunkte', '${s.sampleCount ?? 0}'),
            if (s.lastP1 != null)
              _buildInfoRow(
                'Aktueller Wert',
                '${s.lastP1!.toStringAsFixed(2)} bar / ${s.lastTob1?.toStringAsFixed(1) ?? "-"} °C',
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isStopping ? null : _stopRecording,
                icon: _isStopping
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop),
                label: Text(_isStopping ? 'Wird gestoppt...' : 'Aufzeichnung stoppen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewRecordingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Neue Aufzeichnung',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Bezeichnung',
                prefixIcon: Icon(Icons.label),
                hintText: 'z.B. Heizung OG',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _selectedPN,
              decoration: const InputDecoration(
                labelText: 'Betriebsdruck (PN)',
                prefixIcon: Icon(Icons.compress),
              ),
              items: ValidationService.pnValues.map((pn) {
                return DropdownMenuItem(value: pn, child: Text('PN $pn'));
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedPN = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedMedium,
              decoration: const InputDecoration(
                labelText: 'Medium',
                prefixIcon: Icon(Icons.water_drop),
              ),
              items: const [
                DropdownMenuItem(value: 'air', child: Text('Luft')),
                DropdownMenuItem(value: 'water', child: Text('Wasser')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedMedium = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _intervalController,
              decoration: const InputDecoration(
                labelText: 'Messintervall (Sekunden)',
                prefixIcon: Icon(Icons.timer),
                hintText: '10',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isStarting || !(_health?.sensorConnected ?? false))
                    ? null
                    : _startRecording,
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isStarting
                    ? 'Wird gestartet...'
                    : 'Aufzeichnung starten'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            if (!(_health?.sensorConnected ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kein Drucksensor erkannt. Bitte Sensor pruefen.',
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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
}
