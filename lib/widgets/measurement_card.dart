import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class MeasurementCard extends StatelessWidget {
  final Measurement measurement;
  final VoidCallback? onTap;
  final VoidCallback? onValidate;
  final VoidCallback? onInvalidate;

  const MeasurementCard({
    super.key,
    required this.measurement,
    this.onTap,
    this.onValidate,
    this.onInvalidate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      measurement.filename,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusChip(context),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoItem(
                    context,
                    Icons.access_time,
                    Formatters.formatDateTime(measurement.startTime),
                  ),
                  const SizedBox(width: 16),
                  _buildInfoItem(
                    context,
                    Icons.timer_outlined,
                    Formatters.formatDuration(measurement.duration),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoItem(
                    context,
                    Icons.speed,
                    '${Formatters.formatPressure(measurement.minPressure)} - ${Formatters.formatPressureWithUnit(measurement.maxPressure)}',
                  ),
                  const SizedBox(width: 16),
                  _buildInfoItem(
                    context,
                    Icons.format_list_numbered,
                    '${measurement.samples.length} Messpunkte',
                  ),
                ],
              ),
              if (measurement.validationStatus == ValidationStatus.pending) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onInvalidate,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Ungültig'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onValidate,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Gültig'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (measurement.validationStatus) {
      case ValidationStatus.valid:
        color = Colors.green;
        label = 'Gültig';
        icon = Icons.check_circle;
        break;
      case ValidationStatus.invalid:
        color = Colors.red;
        label = 'Ungültig';
        icon = Icons.cancel;
        break;
      case ValidationStatus.pending:
        color = Colors.orange;
        label = 'Prüfen';
        icon = Icons.help_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[700],
              ),
        ),
      ],
    );
  }
}
