import 'package:flutter/material.dart';

import '../data/favorites.dart';
import '../data/gtfs_db.dart';
import '../data/titsa_realtime.dart';
import 'alarm_entry.dart';

/// Detalle de una parada: llegadas en tiempo real, horario, última guagua,
/// crear alarma y marcar como favorita.
class StopDetailPage extends StatefulWidget {
  final GtfsDb db;
  final TitsaRealtime rt;
  final int stopId;
  final Map<String, Object?>? initialRow;

  const StopDetailPage({
    super.key,
    required this.db,
    required this.rt,
    required this.stopId,
    this.initialRow,
  });

  @override
  State<StopDetailPage> createState() => _StopDetailPageState();
}

class _StopDetailPageState extends State<StopDetailPage> {
  List<Arrival> _arrivals = const [];
  List<ScheduledPassing> _schedule = const [];
  bool _showSchedule = false;
  bool _isFav = false;
  String? _error;
  String _title = 'Parada';
  Map<String, Object?>? _row;

  @override
  void initState() {
    super.initState();
    _row = widget.initialRow;
    _title = (widget.initialRow?['name'] as String?) ?? 'Parada ${widget.stopId}';
    _load();
  }

  Future<void> _load() async {
    _row ??= await widget.db.stopById(widget.stopId);
    final fav = await Favorites.isFavorite(widget.stopId);
    if (mounted) {
      setState(() {
        _isFav = fav;
        _title = (_row?['name'] as String?) ?? _title;
      });
    }
    _loadSchedule();
    await _loadArrivals();
  }

  Future<void> _loadSchedule() async {
    final s = await widget.db.scheduleAtStop(widget.stopId, DateTime.now());
    if (mounted) setState(() => _schedule = s);
  }

  Future<void> _loadArrivals() async {
    setState(() {
      _error = null;
      _arrivals = const [];
    });
    try {
      final a = await widget.rt.arrivals(widget.stopId);
      if (mounted) setState(() => _arrivals = a);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cargar el tiempo real.');
    }
  }

  Future<void> _toggleFav() async {
    final row = _row;
    if (row == null) return;
    final now = await Favorites.toggle(FavStop(
      widget.stopId,
      row['name'] as String,
      (row['lat'] as num).toDouble(),
      (row['lon'] as num).toDouble(),
    ));
    if (mounted) setState(() => _isFav = now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: _isFav ? 'Quitar de favoritas' : 'Añadir a favoritas',
            onPressed: _toggleFav,
            icon: Icon(_isFav ? Icons.star : Icons.star_border,
                color: _isFav ? Colors.amber : null),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadArrivals,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => chooseLineForAlarm(context, widget.db, widget.stopId),
        icon: const Icon(Icons.notifications_active),
        label: const Text('Alarma'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false, label: Text('Tiempo real'), icon: Icon(Icons.wifi)),
                ButtonSegment(
                    value: true, label: Text('Horario'), icon: Icon(Icons.schedule)),
              ],
              selected: {_showSchedule},
              onSelectionChanged: (s) => setState(() => _showSchedule = s.first),
            ),
          ),
          Expanded(child: _showSchedule ? _scheduleList() : _realtimeList()),
        ],
      ),
    );
  }

  Widget _realtimeList() => ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          if (_arrivals.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Toca una línea para crear su alarma de bajada.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          for (final a in _arrivals)
            ListTile(
              leading: CircleAvatar(child: Text('${a.lineId}')),
              title: Text(a.lineDestination),
              trailing: Text('${a.minutesLeft} min',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              onTap: () => chooseLineForAlarm(context, widget.db, widget.stopId,
                  onlyLine: a.lineId),
            ),
          if (_arrivals.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Sin llegadas próximas.')),
            ),
          if (_arrivals.isEmpty && _error != null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin tiempo real. Prueba la pestaña «Horario».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ),
        ],
      );

  Widget _scheduleList() => ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: OutlinedButton.icon(
              onPressed: _showLastDepartures,
              icon: const Icon(Icons.nightlight_round),
              label: const Text('¿Cuál es la última guagua de hoy?'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Salidas teóricas (horario oficial, funciona sin conexión).',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          for (final s in _schedule)
            ListTile(
              leading: CircleAvatar(child: Text(s.lineName)),
              title: Text(s.headsign),
              subtitle: Text(s.hhmm),
              trailing: Text('${s.minutes} min',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onTap: () => chooseLineForAlarm(context, widget.db, widget.stopId,
                  onlyLine: int.tryParse(s.lineName)),
            ),
          if (_schedule.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay más salidas programadas hoy.')),
            ),
        ],
      );

  Future<void> _showLastDepartures() async {
    final last =
        await widget.db.lastDeparturesAtStop(widget.stopId, DateTime.now());
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Última guagua de hoy',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('En rojo, las que ya han pasado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            for (final s in last)
              ListTile(
                leading: CircleAvatar(child: Text(s.lineName)),
                title: Text(s.headsign),
                subtitle: Text('Última a las ${s.hhmm}'),
                trailing: Text(
                  s.minutes < 0 ? 'ya pasó' : 'en ${s.minutes} min',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: s.minutes < 0 ? Colors.red : null),
                ),
              ),
            if (last.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No hay datos de salidas para hoy.')),
              ),
          ],
        ),
      ),
    );
  }
}
