import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../utils/formatters.dart';
import 'signature_screen.dart';

class ProtocolFormScreen extends ConsumerStatefulWidget {
  final Measurement measurement;
  final WeatherData? weatherData;

  const ProtocolFormScreen({
    super.key,
    required this.measurement,
    this.weatherData,
  });

  @override
  ConsumerState<ProtocolFormScreen> createState() => _ProtocolFormScreenState();
}

class _ProtocolFormScreenState extends ConsumerState<ProtocolFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _objectController;
  late TextEditingController _projectController;
  late TextEditingController _authorController;
  late TextEditingController _technicianController;
  late TextEditingController _notesController;
  
  int _selectedPN = 25;
  TestMedium _selectedMedium = TestMedium.air;
  ValidationResult? _validationResult;

  bool get _hasLockedParams => widget.measurement.hasRecordingMetadata;

  @override
  void initState() {
    super.initState();
    _objectController = TextEditingController();
    _projectController = TextEditingController();
    _authorController = TextEditingController();
    _technicianController = TextEditingController();
    _notesController = TextEditingController();

    final meta = widget.measurement.metadata;
    if (meta != null && meta.hasRecordingParams) {
      _selectedPN = meta.pn!;
      _selectedMedium = meta.medium == 'water' ? TestMedium.water : TestMedium.air;
    }
    
    _loadStoredValues();
    _runValidation();
  }

  Future<void> _loadStoredValues() async {
    final storage = ref.read(storageServiceProvider);
    await storage.init();
    
    setState(() {
      _technicianController.text = storage.getTechnicianName();
      _objectController.text = storage.getLastObjectName();
      _projectController.text = storage.getLastProjectName();
    });
  }

  void _runValidation() {
    final validationService = ref.read(validationServiceProvider);
    setState(() {
      _validationResult = validationService.validate(
        widget.measurement,
        _selectedPN,
        _selectedMedium,
        weather: widget.weatherData,
      );
    });
  }

  double get _testPressure => ValidationService.getTestPressure(_selectedPN, _selectedMedium);

  @override
  void dispose() {
    _objectController.dispose();
    _projectController.dispose();
    _authorController.dispose();
    _technicianController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protokoll erstellen'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionCard(
                'Projektinformationen',
                [
                  _buildTextField(
                    controller: _objectController,
                    label: 'Objekt / Anlage',
                    icon: Icons.business,
                  ),
                  _buildTextField(
                    controller: _projectController,
                    label: 'Projekt',
                    icon: Icons.folder,
                  ),
                  _buildTextField(
                    controller: _authorController,
                    label: 'Verfasser',
                    icon: Icons.person_outline,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                'Druckpruefung',
                [
                  _buildPNDropdown(),
                  const SizedBox(height: 8),
                  _buildMediumDropdown(),
                  const SizedBox(height: 12),
                  _buildReadOnlyRow('Pruefdruck', '${Formatters.formatPressure(_testPressure)} bar'),
                  _buildReadOnlyRow('Pruefart', 'Manometer'),
                  _buildReadOnlyRow('Pruefdauer', Formatters.formatDuration(widget.measurement.duration)),
                  _buildReadOnlyRow('Messpunkte', widget.measurement.samples.length.toString()),
                ],
              ),
              const SizedBox(height: 16),
              _buildWeatherCard(),
              const SizedBox(height: 16),
              _buildValidationCard(),
              const SizedBox(height: 16),
              _buildSectionCard(
                'Bemerkungen',
                [
                  _buildTextField(
                    controller: _notesController,
                    label: 'Bemerkungen',
                    icon: Icons.note,
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                'Monteur',
                [
                  _buildTextField(
                    controller: _technicianController,
                    label: 'Name',
                    icon: Icons.badge,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Bitte Namen eingeben';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _continueToSignature,
                icon: const Icon(Icons.draw),
                label: const Text('Weiter zur Unterschrift'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
      ),
    );
  }

  Widget _buildPNDropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _selectedPN,
      decoration: InputDecoration(
        labelText: 'Betriebsdruck (PN)',
        prefixIcon: const Icon(Icons.compress),
        suffixIcon: _hasLockedParams
            ? const Tooltip(
                message: 'Bei Aufzeichnungsstart festgelegt',
                child: Icon(Icons.lock, size: 18),
              )
            : null,
      ),
      items: ValidationService.pnValues.map((pn) {
        return DropdownMenuItem(
          value: pn,
          child: Text('PN $pn'),
        );
      }).toList(),
      onChanged: _hasLockedParams
          ? null
          : (value) {
              if (value != null) {
                setState(() => _selectedPN = value);
                _runValidation();
              }
            },
    );
  }

  Widget _buildMediumDropdown() {
    return DropdownButtonFormField<TestMedium>(
      initialValue: _selectedMedium,
      decoration: InputDecoration(
        labelText: 'Medium',
        prefixIcon: const Icon(Icons.water_drop),
        suffixIcon: _hasLockedParams
            ? const Tooltip(
                message: 'Bei Aufzeichnungsstart festgelegt',
                child: Icon(Icons.lock, size: 18),
              )
            : null,
      ),
      items: TestMedium.values.map((medium) {
        return DropdownMenuItem(
          value: medium,
          child: Text(medium.displayName),
        );
      }).toList(),
      onChanged: _hasLockedParams
          ? null
          : (value) {
              if (value != null) {
                setState(() => _selectedMedium = value);
                _runValidation();
              }
            },
    );
  }

  Widget _buildReadOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    final w = widget.weatherData;

    if (w == null) {
      return Card(
        color: Colors.orange.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wetterdaten nicht verfuegbar',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Validierung nutzt Standard-Toleranz',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.blue.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny, color: Colors.blue, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Wetterdaten',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildReadOnlyRow('Aussentemp. Start', '${w.outdoorTempStart.toStringAsFixed(1)} °C'),
            _buildReadOnlyRow('Aussentemp. Ende', '${w.outdoorTempEnd.toStringAsFixed(1)} °C'),
            _buildReadOnlyRow('Min / Max', '${w.minTemp.toStringAsFixed(1)} / ${w.maxTemp.toStringAsFixed(1)} °C'),
            _buildReadOnlyRow('Schwankung', '${w.tempSwing.toStringAsFixed(1)} °C'),
            if (w.additionalTolerance > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Toleranz wird um ${(w.additionalTolerance * 100).toStringAsFixed(1)}% angepasst',
                  style: TextStyle(color: Colors.blue[700], fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationCard() {
    final result = _validationResult;
    final passed = result?.valid ?? false;
    final color = passed ? Colors.green : Colors.red;

    return Card(
      color: color.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  passed ? Icons.check_circle : Icons.cancel,
                  color: color,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  passed ? 'Resultat: OK' : 'Resultat: Nicht OK',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 12),
              Text(
                result.reason,
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _continueToSignature() async {
    if (!_formKey.currentState!.validate()) return;

    final storage = ref.read(storageServiceProvider);
    await storage.setTechnicianName(_technicianController.text);
    await storage.setLastObjectName(_objectController.text);
    await storage.setLastProjectName(_projectController.text);

    final passed = _validationResult?.valid ?? false;

    final protocolData = ProtocolData(
      measurement: widget.measurement,
      objectName: _objectController.text,
      projectName: _projectController.text,
      author: _authorController.text,
      nominalPressure: _selectedPN,
      testMedium: _selectedMedium,
      testPressure: _testPressure,
      testDuration: Formatters.formatDuration(widget.measurement.duration),
      result: passed ? 'OK' : 'Nicht OK',
      passed: passed,
      technicianName: _technicianController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      validationReason: _validationResult?.reason,
    );

    ref.read(protocolDataProvider.notifier).state = protocolData;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SignatureScreen(protocolData: protocolData),
        ),
      );
    }
  }
}
