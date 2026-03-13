import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../utils/constants.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _portController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _portController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = ref.read(storageServiceProvider);
    await storage.init();
    
    setState(() {
      _nameController.text = storage.getTechnicianName();
      _addressController.text = storage.getPiAddress();
      _portController.text = storage.getPiPort().toString();
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionCard(
                    'Benutzer',
                    Icons.person,
                    [
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Monteur-Name',
                          hintText: 'Max Mustermann',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    'Raspberry Pi Verbindung',
                    Icons.wifi,
                    [
                      TextField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'IP-Adresse',
                          hintText: '192.168.4.1',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '8080',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _testConnection,
                        icon: const Icon(Icons.network_check),
                        label: const Text('Verbindung testen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionCard(
                    'Info',
                    Icons.info_outline,
                    [
                      _buildInfoRow('App-Version', AppConstants.appVersion),
                      _buildInfoRow('App-Name', AppConstants.appName),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
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
          Text(value),
        ],
      ),
    );
  }

  Future<void> _saveSettings() async {
    final storage = ref.read(storageServiceProvider);
    
    await storage.setTechnicianName(_nameController.text);
    await storage.setPiAddress(_addressController.text);
    await storage.setPiPort(int.tryParse(_portController.text) ?? AppConstants.defaultPiPort);
    
    final measurementService = ref.read(measurementServiceProvider);
    measurementService.updatePiConnection(
      _addressController.text,
      int.tryParse(_portController.text) ?? AppConstants.defaultPiPort,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final measurementService = ref.read(measurementServiceProvider);
    measurementService.updatePiConnection(
      _addressController.text,
      int.tryParse(_portController.text) ?? AppConstants.defaultPiPort,
    );
    
    final connected = await measurementService.checkPiConnection();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(connected 
              ? 'Verbindung erfolgreich!' 
              : 'Keine Verbindung zum Pi'),
          backgroundColor: connected ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
