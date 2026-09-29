import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:share_plus/share_plus.dart';

import '../alarm/alarm_service.dart';
import '../alarm/get_off_alarm.dart' show LatLng;
import '../alarm/trip_plan.dart';
import 'alarm_entry.dart';

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
  bool _offRoute = false;
  ll.LatLng? _me;

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
          _offRoute = (data['offRoute'] as bool?) ?? false;
          final lat = (data['lat'] as num?)?.toDouble();
          final lon = (data['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) _me = ll.LatLng(lat, lon);
        case 'ring':
          _ringing = true;
      }
    });
  }

  ll.LatLng _toLL(LatLng p) => ll.LatLng(p.lat, p.lon);

  Future<void> _stop() async {
    await AlarmService.stop();
    if (mounted) Navigator.of(context).pop();
  }

  /// "Cuídame el viaje": comparte el viaje por WhatsApp/SMS/etc. (fase 1).
  Future<void> _shareTrip() async {
    final p = widget.plan;
    final eta = _etaSeconds != null
        ? ' Llego en ~${(_etaSeconds! / 60).ceil()} min.'
        : '';
    final msg = _arrived
        ? 'He llegado a ${p.destination.name} (línea ${p.lineName}). 🚌'
        : 'Voy en la guagua línea ${p.lineName} hacia ${p.destination.name}.'
            '$eta Te aviso al llegar. 🚌';
    await Share.share(msg, subject: 'Mi viaje en guagua');
  }

  @override
  Widget build(BuildContext context) {
    final dest = widget.plan.destination.name;
    final eta = _etaSeconds == null ? '—' : '${(_etaSeconds! / 60).ceil()} min';
    return Scaffold(
      appBar: AppBar(title: Text('Línea ${widget.plan.lineName}')),
      body: Column(
        children: [
          SizedBox(height: 200, child: _tripMap()),
          // Zona de información desplazable (evita que se corte en pantallas
          // pequeñas o con teclado/barras del sistema).
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Te bajas en',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(dest,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
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
                  if (_offRoute && !_ringing && !_arrived)
                    Card(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(Icons.help_outline),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'Posición incierta. Comprueba que vas en el sentido correcto.'),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _metric('Paradas restantes',
                      _stopsRemaining == null ? '—' : '$_stopsRemaining'),
                  _metric('Distancia',
                      _metersRemaining == null
                          ? '—'
                          : '${_metersRemaining!.round()} m'),
                  _metric('Tiempo estimado', eta),
                ],
              ),
            ),
          ),
          // Botones siempre visibles, respetando la barra de gestos.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _shareTrip,
                    icon: const Icon(Icons.share),
                    label: Text(_arrived
                        ? 'Avisar de que he llegado'
                        : 'Avisar a alguien'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Detener seguimiento'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripMap() {
    final plan = widget.plan;
    final shape = plan.shape.map(_toLL).toList();
    final center = _me ??
        (shape.isNotEmpty
            ? shape[shape.length ~/ 2]
            : _toLL(plan.destination.pos));
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 14,
        interactionOptions:
            const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        TileLayer(
          urlTemplate: osmTileUrl,
          userAgentPackageName: tileUserAgentPackage,
          maxZoom: 19,
        ),
        if (shape.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: shape,
              strokeWidth: 5,
              color: const Color(0xFF2E7D32),
            ),
          ]),
        MarkerLayer(markers: [
          // Parada de destino resaltada.
          Marker(
            point: _toLL(plan.destination.pos),
            width: 40,
            height: 40,
            child: const Icon(Icons.place, color: Colors.red, size: 38),
          ),
          if (_me != null)
            Marker(
              point: _me!,
              width: 20,
              height: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
        ]),
      ],
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
