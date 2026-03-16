import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import 'protocol_form_screen.dart';

class InternetCheckScreen extends ConsumerStatefulWidget {
  final Measurement measurement;

  const InternetCheckScreen({
    super.key,
    required this.measurement,
  });

  @override
  ConsumerState<InternetCheckScreen> createState() =>
      _InternetCheckScreenState();
}

class _InternetCheckScreenState extends ConsumerState<InternetCheckScreen> {
  bool _checking = true;
  bool _connected = false;
  bool _fetchingWeather = false;
  bool _rebootSent = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _sendRebootAndCheck();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendRebootAndCheck() async {
    if (!_rebootSent) {
      try {
        final service = ref.read(measurementServiceProvider);
        await service.recorderConnection.turnOffWifi();
      } catch (_) {}
      _rebootSent = true;
      // Give the Pi 3s to shut down WiFi before checking internet
      await Future.delayed(const Duration(seconds: 3));
    }
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);

    bool hasInternet;
    try {
      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      hasInternet = response.statusCode == 200;
    } catch (_) {
      hasInternet = false;
    }

    if (mounted) {
      setState(() {
        _checking = false;
        _connected = hasInternet;
      });

      if (hasInternet) {
        _onConnected();
      } else {
        _retryTimer?.cancel();
        _retryTimer = Timer(const Duration(seconds: 3), _checkConnection);
      }
    }
  }

  Future<void> _onConnected() async {
    setState(() => _fetchingWeather = true);

    // Upload raw CSV to cloud immediately (best-effort, don't block)
    _uploadRawCsv();

    WeatherData? weatherData;
    try {
      final weatherService = ref.read(weatherServiceProvider);
      weatherData = await weatherService.fetchForPeriod(
        widget.measurement.startTime,
        widget.measurement.endTime,
      );
    } catch (_) {}

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ProtocolFormScreen(
            measurement: widget.measurement,
            weatherData: weatherData,
          ),
        ),
      );
    }
  }

  Future<void> _uploadRawCsv() async {
    try {
      final supabaseService = ref.read(supabaseUploadServiceProvider);
      if (!supabaseService.isConfigured) return;

      final measurementService = ref.read(measurementServiceProvider);
      final csvContent = measurementService.exportToCsv(widget.measurement);
      final name = widget.measurement.metadata?.name ?? widget.measurement.filename;

      await supabaseService.uploadRawMeasurement(
        csvContent: csvContent,
        measurementName: name,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Internetverbindung'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_fetchingWeather) ...[
                const Icon(Icons.cloud_download, size: 64, color: Colors.blue),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Standort & Wetterdaten werden abgerufen...',
                  style: TextStyle(fontSize: 16),
                ),
              ] else if (_checking) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Internetverbindung wird geprueft...',
                  style: TextStyle(fontSize: 16),
                ),
              ] else if (!_connected) ...[
                const Icon(Icons.wifi_off, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                Text(
                  'Keine Internetverbindung',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Das Prezio Recorder WLAN wurde abgeschaltet.\n'
                  'Es startet automatisch in ca. 2 Minuten neu.\n'
                  'Bitte mit normalem WiFi oder Mobilfunk verbinden.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildStep('1', 'Einstellungen > WLAN oeffnen'),
                      const SizedBox(height: 8),
                      _buildStep('2', 'Normales WiFi verbinden oder Mobilfunk nutzen'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Pruefe automatisch alle 3 Sekunden...',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _checkConnection,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Jetzt pruefen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.blue,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}
