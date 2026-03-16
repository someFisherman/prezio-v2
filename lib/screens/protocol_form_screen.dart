import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/services.dart';
import '../utils/formatters.dart';
import '../widgets/widgets.dart';
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
  late TextEditingController _locationController;

  int _selectedPN = 25;
  TestMedium _selectedMedium = TestMedium.air;
  late TestProfile _selectedProfile;
  ValidationResult? _validationResult;
  List<NominatimPlace> _locationSuggestions = [];
  Timer? _searchDebounce;
  double? _latitude;
  double? _longitude;

  // Custom profile overrides
  late TextEditingController _customHoldHoursController;
  late TextEditingController _customMaxDropController;
  late TextEditingController _customFactorController;
  late TextEditingController _customRatioController;
  late TextEditingController _customGapController;

  bool get _hasLockedParams => widget.measurement.hasRecordingMetadata;

  @override
  void initState() {
    super.initState();
    _objectController = TextEditingController();
    _projectController = TextEditingController();
    _authorController = TextEditingController();
    _technicianController = TextEditingController();
    _notesController = TextEditingController();
    _locationController = TextEditingController();

    final meta = widget.measurement.metadata;
    if (meta != null && meta.hasRecordingParams) {
      _selectedPN = meta.pn!;
      _selectedMedium = meta.medium == 'water' ? TestMedium.water : TestMedium.air;
    }

    _selectedProfile = TestProfile.findForMedium(_selectedMedium) ??
        TestProfile.defaultProfiles.first;

    _customHoldHoursController =
        TextEditingController(text: _selectedProfile.holdDurationHours.toString());
    _customMaxDropController =
        TextEditingController(text: _selectedProfile.maxPressureDropBar.toString());
    _customFactorController =
        TextEditingController(text: _selectedProfile.pressureFactor.toString());
    _customRatioController =
        TextEditingController(text: _selectedProfile.minValidPressureRatio.toString());
    _customGapController =
        TextEditingController(text: _selectedProfile.maxDataGapSeconds.toString());

    _loadStoredValues();
    _runValidation();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _latitude = position.latitude;
      _longitude = position.longitude;

      final nominatim = ref.read(nominatimServiceProvider);
      final place = await nominatim.reverseGeocode(position.latitude, position.longitude);
      if (place != null && mounted) {
        setState(() {
          _locationController.text = place.displayName;
        });
      }
    } catch (_) {}
  }

  Future<void> _searchLocation(String query) async {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _locationSuggestions = []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      final nominatim = ref.read(nominatimServiceProvider);
      final results = await nominatim.search(query);
      if (mounted) {
        setState(() => _locationSuggestions = results);
      }
    });
  }

  void _selectLocation(NominatimPlace place) {
    setState(() {
      _locationController.text = place.displayName;
      _latitude = place.lat;
      _longitude = place.lon;
      _locationSuggestions = [];
    });
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

  TestProfile get _activeProfile {
    if (!_selectedProfile.isCustom) return _selectedProfile;

    return _selectedProfile.copyWith(
      medium: _selectedMedium,
      pressureFactor: double.tryParse(_customFactorController.text) ?? 1.5,
      holdDurationHours: double.tryParse(_customHoldHoursController.text) ?? 1.0,
      minValidPressureRatio: double.tryParse(_customRatioController.text) ?? 0.98,
      maxPressureDropBar: double.tryParse(_customMaxDropController.text) ?? 0.2,
      maxDataGapSeconds: int.tryParse(_customGapController.text) ?? 60,
    );
  }

  void _runValidation() {
    final validationService = ref.read(validationServiceProvider);
    setState(() {
      _validationResult = validationService.validate(
        widget.measurement,
        _selectedPN,
        _activeProfile,
        weather: widget.weatherData,
      );
    });
  }

  double get _testPressure => _activeProfile.getRequiredPressure(_selectedPN);

  @override
  void dispose() {
    _objectController.dispose();
    _projectController.dispose();
    _authorController.dispose();
    _technicianController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    _customHoldHoursController.dispose();
    _customMaxDropController.dispose();
    _customFactorController.dispose();
    _customRatioController.dispose();
    _customGapController.dispose();
    _searchDebounce?.cancel();
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
              _buildLocationCard(),
              const SizedBox(height: 16),
              _buildPressureTestCard(),
              const SizedBox(height: 16),
              _buildWeatherCard(),
              const SizedBox(height: 16),
              _buildValidationCard(),
              const SizedBox(height: 16),
              _buildChartCard(),
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

  Widget _buildPressureTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Druckpruefung',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildProfileDropdown(),
            const SizedBox(height: 12),
            _buildPNDropdown(),
            const SizedBox(height: 8),
            _buildMediumDropdown(),
            if (_selectedProfile.isCustom) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text('Benutzerdefinierte Parameter',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                    fontSize: 13,
                  )),
              const SizedBox(height: 12),
              _buildCustomParamField(
                controller: _customFactorController,
                label: 'Druckfaktor (x PN)',
                suffix: 'x',
              ),
              _buildCustomParamField(
                controller: _customHoldHoursController,
                label: 'Haltezeit',
                suffix: 'h',
              ),
              _buildCustomParamField(
                controller: _customMaxDropController,
                label: 'Max. Druckabfall',
                suffix: 'bar',
              ),
              _buildCustomParamField(
                controller: _customRatioController,
                label: 'Min. Druck-Ratio',
                suffix: '',
              ),
              _buildCustomParamField(
                controller: _customGapController,
                label: 'Max. Datenluecke',
                suffix: 's',
              ),
            ],
            const SizedBox(height: 12),
            _buildReadOnlyRow('Pruefdruck', '${Formatters.formatPressure(_testPressure)} bar'),
            _buildReadOnlyRow('Pruefart', 'Manometer'),
            _buildReadOnlyRow('Pruefdauer', Formatters.formatDuration(widget.measurement.duration)),
            _buildReadOnlyRow('Messpunkte', widget.measurement.samples.length.toString()),
            if (!_selectedProfile.isCustom) ...[
              _buildReadOnlyRow('Haltezeit (Soll)', '${_selectedProfile.holdDurationHours}h'),
              _buildReadOnlyRow('Max. Druckabfall', '${_selectedProfile.maxPressureDropBar} bar'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomParamField({
    required TextEditingController controller,
    required String label,
    required String suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _runValidation(),
      ),
    );
  }

  Widget _buildProfileDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedProfile.id,
      decoration: const InputDecoration(
        labelText: 'Pruefprofil',
        prefixIcon: Icon(Icons.tune),
      ),
      items: TestProfile.defaultProfiles.map((p) {
        return DropdownMenuItem(
          value: p.id,
          child: Text(p.name),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          final profile = TestProfile.defaultProfiles.firstWhere((p) => p.id == value);
          setState(() {
            _selectedProfile = profile;
            if (!profile.isCustom) {
              _selectedMedium = profile.medium;
            }
            _customHoldHoursController.text = profile.holdDurationHours.toString();
            _customMaxDropController.text = profile.maxPressureDropBar.toString();
            _customFactorController.text = profile.pressureFactor.toString();
            _customRatioController.text = profile.minValidPressureRatio.toString();
            _customGapController.text = profile.maxDataGapSeconds.toString();
          });
          _runValidation();
        }
      },
    );
  }

  Widget _buildLocationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Standort der Messung',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Standort',
                hintText: 'Wird automatisch ermittelt...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _locationController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _locationController.clear();
                          setState(() => _locationSuggestions = []);
                        },
                      )
                    : null,
              ),
              onChanged: _searchLocation,
            ),
            if (_locationSuggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _locationSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final place = _locationSuggestions[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place, size: 18),
                      title: Text(
                        place.displayName,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectLocation(place),
                    );
                  },
                ),
              ),
            ],
            if (_latitude != null && _longitude != null) ...[
              const SizedBox(height: 8),
              Text(
                'GPS: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ],
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
      items: TestProfile.pnValues.map((pn) {
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
    final passed = result?.isPassed ?? false;
    final isValid = result?.isValidMeasurement ?? false;
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
              _buildReadOnlyRow('Profil', result.profileName),
              _buildReadOnlyRow(
                'Pruefdruck (Soll)',
                '${Formatters.formatPressure(result.requiredPressureBar)} bar',
              ),
              if (isValid) ...[
                _buildReadOnlyRow(
                  'Erkannte Haltezeit',
                  _formatHours(result.detectedHoldDurationHours),
                ),
                _buildReadOnlyRow(
                  'Druckabfall',
                  '${result.pressureDropBar.toStringAsFixed(3)} bar',
                ),
                if (result.evaluationWindowStart != null)
                  _buildReadOnlyRow(
                    'Prueffenster',
                    '${Formatters.formatDateTime(result.evaluationWindowStart!)} - '
                        '${Formatters.formatTime(result.evaluationWindowEnd!)}',
                  ),
              ],
              const SizedBox(height: 8),
              ...result.failureReasons.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          passed ? Icons.info_outline : Icons.warning_amber_rounded,
                          size: 16,
                          color: passed ? Colors.green[700] : Colors.red[700],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              color: passed ? Colors.green[800] : Colors.red[800],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  String _formatHours(double hours) {
    if (hours < 1.0) {
      final mins = (hours * 60).round();
      return '${mins}min';
    }
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  Widget _buildChartCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Druckverlauf',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PressureChart(
              measurement: widget.measurement,
              height: 220,
            ),
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

    final passed = _validationResult?.isPassed ?? false;
    final profile = _activeProfile;

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
      location: _locationController.text.isEmpty ? null : _locationController.text,
      latitude: _latitude,
      longitude: _longitude,
      testProfileId: profile.id,
      testProfileName: profile.name,
      detectedHoldDurationHours: _validationResult?.detectedHoldDurationHours ?? 0.0,
      pressureDropBar: _validationResult?.pressureDropBar ?? 0.0,
      failureReasons: _validationResult?.failureReasons ?? [],
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
