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
  bool _oneDriveConnected = false;
  bool _oneDriveLoggingIn = false;

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

    final oneDrive = ref.read(oneDriveServiceProvider);
    final savedToken = storage.getOneDriveRefreshToken();
    if (AppConstants.azureClientId.isNotEmpty && savedToken != null) {
      oneDrive.configure(
        clientId: AppConstants.azureClientId,
        savedRefreshToken: savedToken,
      );
    }

    setState(() {
      _nameController.text = storage.getTechnicianName();
      _addressController.text = storage.getPiAddress();
      _portController.text = storage.getPiPort().toString();
      _oneDriveConnected = oneDrive.isConnected;
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

  Future<void> _loginOneDrive() async {
    if (AppConstants.azureClientId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Azure Client-ID fehlt. Bitte in constants.dart eintragen.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _oneDriveLoggingIn = true);

    final oneDrive = ref.read(oneDriveServiceProvider);
    oneDrive.configure(clientId: AppConstants.azureClientId);

    final refreshToken = await oneDrive.login();

    if (refreshToken != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setOneDriveRefreshToken(refreshToken);

      if (mounted) {
        setState(() {
          _oneDriveConnected = true;
          _oneDriveLoggingIn = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OneDrive verbunden')),
        );
      }
    } else {
      if (mounted) {
        setState(() => _oneDriveLoggingIn = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OneDrive-Anmeldung fehlgeschlagen'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logoutOneDrive() async {
    final oneDrive = ref.read(oneDriveServiceProvider);
    oneDrive.logout();

    final storage = ref.read(storageServiceProvider);
    await storage.setOneDriveRefreshToken(null);

    setState(() => _oneDriveConnected = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OneDrive getrennt')),
      );
    }
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
                  _buildOneDriveCard(),
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
                        keyboardType: TextInputType.url,
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

  Widget _buildOneDriveCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _oneDriveConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: _oneDriveConnected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'OneDrive',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_oneDriveConnected) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Verbunden - Protokolle werden automatisch hochgeladen',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Zielordner: OneDrive > Prezio > Protokolle',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _logoutOneDrive,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('OneDrive trennen'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ] else ...[
              Text(
                'Protokolle werden nur lokal gespeichert. '
                'Mit Microsoft anmelden fuer automatische OneDrive-Synchronisation.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              if (AppConstants.azureClientId.isEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Azure Client-ID noch nicht konfiguriert. '
                    'Siehe constants.dart',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _oneDriveLoggingIn ? null : _loginOneDrive,
                  icon: _oneDriveLoggingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(_oneDriveLoggingIn
                      ? 'Anmeldung laeuft...'
                      : 'Mit Microsoft anmelden'),
                ),
              ),
            ],
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
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
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
    await storage.setPiPort(
        int.tryParse(_portController.text) ?? AppConstants.defaultPiPort);

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
}
