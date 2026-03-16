import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../providers/providers.dart';
import '../utils/constants.dart';
import 'recorder_screen.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  Timer? _pollTimer;
  bool _connecting = false;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _statusText = 'Bitte mit Prezio Recorder WLAN verbinden';
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _tryConnect();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_connecting) _tryConnect();
    });
  }

  Future<void> _tryConnect() async {
    _connecting = true;
    final service = ref.read(measurementServiceProvider);
    final baseUrl = service.recorderConnection.baseUrl;

    try {
      final healthResp = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));

      if (healthResp.statusCode != 200) {
        if (mounted) setState(() => _statusText = 'Prezio Recorder nicht erreichbar');
        _connecting = false;
        return;
      }

      if (mounted) setState(() => _statusText = 'Recorder gefunden, authentifiziere...');

      final keyResp = await http
          .get(Uri.parse('$baseUrl/auth/key'))
          .timeout(const Duration(seconds: 3));

      if (keyResp.statusCode == 200) {
        final data = jsonDecode(keyResp.body);
        final key = data['key'] as String?;

        if (key != null && key.isNotEmpty) {
          _pollTimer?.cancel();
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RecorderScreen()),
            );
          }
          return;
        }
      }

      if (mounted) setState(() => _statusText = 'Authentifizierung fehlgeschlagen');
    } catch (_) {
      if (mounted) setState(() => _statusText = 'Bitte mit Prezio Recorder WLAN verbinden');
    } finally {
      _connecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/images/kolibri.png',
                    width: 160,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Prezio',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Druckprotokoll-App',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 24),
                Text(
                  _statusText ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildStep('1', 'Prezio Recorder einschalten'),
                      const SizedBox(height: 8),
                      _buildStep('2', 'WLAN "Prezio-Recorder" verbinden'),
                      const SizedBox(height: 8),
                      _buildStep('3', 'Verbindung wird automatisch erkannt'),
                    ],
                  ),
                ),
              ],
            ),
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
            color: Theme.of(context).colorScheme.primary,
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
