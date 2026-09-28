import 'package:flutter/material.dart';

import '../alarm/alarm_service.dart';
import '../alarm/get_off_alarm.dart';
import '../alarm/reliability.dart';
import '../alarm/trip_plan.dart';
import '../data/gtfs_db.dart';
import 'reliability_page.dart';
import 'tracking_page.dart';

/// Configura la alarma de bajada: elige la parada de destino y cuándo avisar,
/// partiendo de un patrón (línea + sentido) y la parada en la que subes.
class TripSetupPage extends StatefulWidget {
  final GtfsDb db;
  final int patternId;
  final String? shapeId;
  final String lineName;
  final String headsign;

  /// Parada en la que el usuario sube (para ofrecer solo destinos posteriores).
  final int boardingStopId;

  const TripSetupPage({
    super.key,
    required this.db,
    required this.patternId,
    required this.shapeId,
    required this.lineName,
    required this.headsign,
    required this.boardingStopId,
  });

  @override
  State<TripSetupPage> createState() => _TripSetupPageState();
}

class _TripSetupPageState extends State<TripSetupPage> {
  List<TripStop> _stops = const [];
  List<LatLng> _shape = const [];
  int _boardingIndex = 0;
  int? _destIndex;
  TriggerKind _kind = TriggerKind.stopsBefore;
  int _value = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.db
        .patternStopsAndShape(widget.patternId, widget.shapeId);
    var bi = r.stops.indexWhere((s) => s.stopId == widget.boardingStopId);
    if (bi < 0) bi = 0;
    setState(() {
      _stops = r.stops;
      _shape = r.shape;
      _boardingIndex = bi;
    });
  }

  AlarmConfig _config() => switch (_kind) {
        TriggerKind.stopsBefore => AlarmConfig.stopsBefore(_value),
        TriggerKind.metersBefore => AlarmConfig.metersBefore(_value),
        TriggerKind.minutesBefore => AlarmConfig.minutesBefore(_value),
      };

  Future<void> _start() async {
    final ok = await AlarmService.ensurePermissions();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Necesito permiso de ubicación para la alarma.'),
        ));
      }
      return;
    }
    final plan = TripPlan(
      patternId: widget.patternId,
      lineName: widget.lineName,
      headsign: widget.headsign,
      destIndex: _destIndex!,
      stops: _stops,
      shape: _shape,
      config: _config(),
    );
    // Aviso proactivo si el fabricante puede matar el servicio en 2º plano.
    final rel = await Reliability.check();
    if (mounted && !rel.batteryUnrestricted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Para que la alarma no falle'),
          content: const Text(
              'Tu móvil puede cerrar la app en segundo plano y la alarma no '
              'sonaría. Revisa la fiabilidad antes de empezar.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Empezar igualmente')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Revisar')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ReliabilityPage(),
        ));
      }
    }

    await AlarmService.start(plan);
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => TrackingPage(plan: plan),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _stops
        .asMap()
        .entries
        .where((e) => e.key > _boardingIndex)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('Alarma · Línea ${widget.lineName}')),
      body: _stops.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: Text('Subes en: ${_stops[_boardingIndex].name}'),
                  subtitle: Text('Sentido: ${widget.headsign}'),
                ),
                const Divider(height: 1),
                _triggerSelector(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('¿Dónde te bajas?',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final e in destinations)
                        RadioListTile<int>(
                          value: e.key,
                          groupValue: _destIndex,
                          title: Text(e.value.name),
                          secondary: Text('Parada ${e.value.stopId}'),
                          onChanged: (v) => setState(() => _destIndex = v),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: _destIndex == null ? null : _start,
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Iniciar alarma de bajada'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<int> _valuesFor(TriggerKind k) => switch (k) {
        TriggerKind.stopsBefore => const [1, 2, 3, 4, 5],
        TriggerKind.minutesBefore => const [1, 2, 3, 5, 10],
        TriggerKind.metersBefore => const [100, 200, 300, 500, 1000],
      };

  Widget _triggerSelector() {
    final values = _valuesFor(_kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('Avisar '),
          DropdownButton<int>(
            value: _value,
            items: values
                .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                .toList(),
            onChanged: (v) => setState(() => _value = v ?? _value),
          ),
          const SizedBox(width: 8),
          DropdownButton<TriggerKind>(
            value: _kind,
            items: const [
              DropdownMenuItem(
                  value: TriggerKind.stopsBefore, child: Text('paradas antes')),
              DropdownMenuItem(
                  value: TriggerKind.minutesBefore, child: Text('minutos antes')),
              DropdownMenuItem(
                  value: TriggerKind.metersBefore, child: Text('metros antes')),
            ],
            onChanged: (v) => setState(() {
              _kind = v ?? _kind;
              // Ajusta el valor al conjunto válido del nuevo tipo.
              final vs = _valuesFor(_kind);
              if (!vs.contains(_value)) _value = vs[1];
            }),
          ),
        ],
      ),
    );
  }
}
