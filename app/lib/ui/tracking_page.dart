import 'package:flutter/material.dart';

import '../alarm/alarm_service.dart';
import '../alarm/trip_plan.dart';

/// Muestra el progreso del viaje mientras el servicio en segundo plano sigue el
/// GPS. Recibe actualizaciones del servicio vía [AlarmService.addListener].
class TrackingPage extends StatefulWidget {
  final TripPlan plan;
  const TrackingPage({super.key, required this.plan});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  int? _stopsRemaining;
  double? _metersRemaining;
  int? _etaSeconds;
  bool _arrived = false;
  bool _ringing = false;

  @override
  void initState() {
    super.initState();
    AlarmService.addListener(_onData);
  }

  void _onData(Object data) {
    if (data is! Map) return;
    setState(() {
      switch (data['type']) {
        case 'status':
          _stopsRemaining = data['stopsRemaining'] as int?;
          _metersRemaining = (data['metersRemaining'] as num?)?.toDouble();
          _etaSeconds = data['etaSeconds'] as int?;
          _arrived = (data['arrived'] as bool?) ?? false;
        case 'ring':
          _ringing = true;
      }
    });
  }

  Future<void> _stop() async {
    await AlarmService.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dest = widget.plan.destination.name;
    final eta = _etaSeconds == null ? '—' : '${(_etaSeconds! / 60).ceil()} min';
    return Scaffold(
      appBar: AppBar(title: Text('Línea ${widget.plan.lineName}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Te bajas en', style: Theme.of(context).textTheme.titleMedium),
            Text(dest,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            if (_ringing || _arrived)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Row(children: [
                    Icon(Icons.notifications_active, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('¡Prepárate para bajar!',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            _metric('Paradas restantes',
                _stopsRemaining == null ? '—' : '$_stopsRemaining'),
            _metric('Distancia',
                _metersRemaining == null
                    ? '—'
                    : '${_metersRemaining!.round()} m'),
            _metric('Tiempo estimado', eta),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop),
              label: const Text('Detener seguimiento'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      );

  @override
  void dispose() {
    AlarmService.removeListener(_onData);
    super.dispose();
  }
}
