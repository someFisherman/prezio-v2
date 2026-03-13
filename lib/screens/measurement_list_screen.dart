import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../widgets/widgets.dart';
import 'measurement_detail_screen.dart';

class MeasurementListScreen extends ConsumerStatefulWidget {
  const MeasurementListScreen({super.key});

  @override
  ConsumerState<MeasurementListScreen> createState() => _MeasurementListScreenState();
}

class _MeasurementListScreenState extends ConsumerState<MeasurementListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final measurements = ref.watch(measurementsProvider);
    
    final pending = measurements.where((m) => m.validationStatus == ValidationStatus.pending).toList();
    final valid = measurements.where((m) => m.validationStatus == ValidationStatus.valid).toList();
    final invalid = measurements.where((m) => m.validationStatus == ValidationStatus.invalid).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messungen'),
        actions: [
          if (pending.isNotEmpty)
            TextButton.icon(
              onPressed: _markAllAsValid,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Alle gültig'),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _showClearDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Alle löschen'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.help_outline, size: 18),
                  const SizedBox(width: 4),
                  Text('Prüfen (${pending.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 18),
                  const SizedBox(width: 4),
                  Text('Gültig (${valid.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cancel, size: 18),
                  const SizedBox(width: 4),
                  Text('Ungültig (${invalid.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMeasurementList(pending, canValidate: true),
          _buildMeasurementList(valid, canSelect: true),
          _buildMeasurementList(invalid),
        ],
      ),
    );
  }

  Widget _buildMeasurementList(
    List<Measurement> measurements, {
    bool canValidate = false,
    bool canSelect = false,
  }) {
    if (measurements.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Keine Messungen',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: measurements.length,
      itemBuilder: (context, index) {
        final measurement = measurements[index];
        return MeasurementCard(
          measurement: measurement,
          onTap: canSelect
              ? () => _navigateToDetail(measurement)
              : (canValidate ? null : () => _showInvalidMeasurementInfo(measurement)),
          onValidate: canValidate
              ? () => _setValidationStatus(measurement.id, ValidationStatus.valid)
              : null,
          onInvalidate: canValidate
              ? () => _setValidationStatus(measurement.id, ValidationStatus.invalid)
              : null,
        );
      },
    );
  }

  void _setValidationStatus(String id, ValidationStatus status) {
    ref.read(measurementsProvider.notifier).setValidationStatus(id, status);
  }

  void _markAllAsValid() {
    ref.read(measurementsProvider.notifier).markAllAsValid();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alle Messungen als gültig markiert')),
    );
  }

  void _navigateToDetail(Measurement measurement) {
    ref.read(selectedMeasurementProvider.notifier).state = measurement;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementDetailScreen(measurement: measurement),
      ),
    );
  }

  void _showInvalidMeasurementInfo(Measurement measurement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ungültige Messung'),
        content: Text(
          'Diese Messung wurde als ungültig markiert.\n\n'
          'Datei: ${measurement.filename}\n'
          '${measurement.validationReason != null ? 'Grund: ${measurement.validationReason}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alle löschen?'),
        content: const Text('Alle geladenen Messungen werden entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () {
              ref.read(measurementsProvider.notifier).clearAll();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}
