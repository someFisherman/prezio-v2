import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/formatters.dart';
import 'signature_screen.dart';

class ProtocolFormScreen extends ConsumerStatefulWidget {
  final Measurement measurement;

  const ProtocolFormScreen({
    super.key,
    required this.measurement,
  });

  @override
  ConsumerState<ProtocolFormScreen> createState() => _ProtocolFormScreenState();
}

class _ProtocolFormScreenState extends ConsumerState<ProtocolFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _objectController;
  late TextEditingController _projectController;
  late TextEditingController _authorController;
  late TextEditingController _nominalPressureController;
  late TextEditingController _testPressureController;
  late TextEditingController _technicianController;
  late TextEditingController _notesController;
  
  TestMedium _selectedMedium = TestMedium.air;
  final Set<TestType> _selectedTestTypes = {};
  bool _passed = true;

  @override
  void initState() {
    super.initState();
    _objectController = TextEditingController();
    _projectController = TextEditingController();
    _authorController = TextEditingController();
    _nominalPressureController = TextEditingController(text: '25');
    _testPressureController = TextEditingController(
      text: Formatters.formatPressure(widget.measurement.maxPressure),
    );
    _technicianController = TextEditingController();
    _notesController = TextEditingController();
    
    _loadStoredValues();
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

  @override
  void dispose() {
    _objectController.dispose();
    _projectController.dispose();
    _authorController.dispose();
    _nominalPressureController.dispose();
    _testPressureController.dispose();
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
                'Druckprüfung',
                [
                  _buildTextField(
                    controller: _nominalPressureController,
                    label: 'Betriebsdruck (PN)',
                    icon: Icons.compress,
                    keyboardType: TextInputType.number,
                    hint: 'z.B. 25 für PN 25',
                  ),
                  const SizedBox(height: 8),
                  _buildDropdownField(),
                  const SizedBox(height: 4),
                  _buildTextField(
                    controller: _testPressureController,
                    label: 'Prüfdruck (bar)',
                    icon: Icons.speed,
                    keyboardType: TextInputType.number,
                  ),
                  _buildInfoRow('Prüfdauer', Formatters.formatDuration(widget.measurement.duration)),
                  _buildInfoRow('Messpunkte', widget.measurement.samples.length.toString()),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                'Prüfart',
                [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TestType.values.map((type) {
                      final isSelected = _selectedTestTypes.contains(type);
                      return FilterChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTestTypes.add(type);
                            } else {
                              _selectedTestTypes.remove(type);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                'Resultat',
                [
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('Bestanden'),
                          value: true,
                          groupValue: _passed,
                          onChanged: (value) {
                            setState(() => _passed = value!);
                          },
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('Nicht bestanden'),
                          value: false,
                          groupValue: _passed,
                          onChanged: (value) {
                            setState(() => _passed = value!);
                          },
                        ),
                      ),
                    ],
                  ),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
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

  Widget _buildDropdownField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<TestMedium>(
        value: _selectedMedium,
        decoration: const InputDecoration(
          labelText: 'Druckprüfung (Medium)',
          prefixIcon: Icon(Icons.water_drop),
        ),
        items: TestMedium.values.map((medium) {
          return DropdownMenuItem(
            value: medium,
            child: Text(medium.displayName),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _selectedMedium = value);
          }
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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

  Future<void> _continueToSignature() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final storage = ref.read(storageServiceProvider);
    await storage.setTechnicianName(_technicianController.text);
    await storage.setLastObjectName(_objectController.text);
    await storage.setLastProjectName(_projectController.text);

    final protocolData = ProtocolData(
      measurement: widget.measurement,
      objectName: _objectController.text,
      projectName: _projectController.text,
      author: _authorController.text,
      nominalPressure: int.tryParse(_nominalPressureController.text) ?? 0,
      testMedium: _selectedMedium,
      testPressure: double.tryParse(_testPressureController.text) ?? 0.0,
      testDuration: Formatters.formatDuration(widget.measurement.duration),
      testTypes: _selectedTestTypes.toList(),
      result: _passed ? 'OK' : 'Nicht OK',
      passed: _passed,
      technicianName: _technicianController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
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
