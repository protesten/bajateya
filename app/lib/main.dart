import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'alarm/alarm_service.dart';
import 'data/data_updater.dart';
import 'data/gtfs_db.dart';
import 'data/titsa_realtime.dart';
import 'alarm/trip_plan.dart';
import 'data/favorites.dart';
import 'ui/alarm_entry.dart';
import 'ui/data_update_ui.dart';
import 'ui/map_page.dart';
import 'ui/settings_page.dart';
import 'ui/tracking_page.dart';

/// Clave SAE inyectada en compilación:
///   flutter run --dart-define=TITSA_ID_APP=xxxxxxxx
const String kIdApp = String.fromEnvironment('TITSA_ID_APP');

/// URL del manifest de datos (release "gtfs" del repositorio en GitHub).
/// Reemplaza OWNER/REPO por el repositorio real, o inyéctalo con
/// --dart-define=DATA_MANIFEST_URL=...
const String kManifestUrl = String.fromEnvironment('DATA_MANIFEST_URL',
    defaultValue:
        'https://github.com/protesten/bajateya/releases/download/gtfs/manifest.json');

const String kAppVersion = '0.1.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  await AlarmService.init();
  runApp(const BajateAquiApp());
}

class BajateAquiApp extends StatelessWidget {
  const BajateAquiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bájate Aquí',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF75AD1C), // verde TITSA
        useMaterial3: true,
      ),
      home: const StopSearchPage(),
    );
  }
}

/// Pantalla mínima: buscar parada y ver llegadas en tiempo real.
class StopSearchPage extends StatefulWidget {
  const StopSearchPage({super.key});

  @override
  State<StopSearchPage> createState() => _StopSearchPageState();
}

class _StopSearchPageState extends State<StopSearchPage> {
  final _db = GtfsDb();
  final _rt = TitsaRealtime(idApp: kIdApp);
  List<Map<String, Object?>> _stops = const [];
  List<Arrival> _arrivals = const [];
  int? _selected;
  Map<String, Object?>? _selectedRow; // parada seleccionada (para favorito)
  bool _selectedIsFav = false;
  bool _showSchedule = false; // pestaña Tiempo real / Horario
  List<ScheduledPassing> _schedule = const [];
  String? _error;
  List<FavStop> _favs = const [];
  final _updater =
      DataUpdater(manifestUrl: kManifestUrl, appVersion: kAppVersion);

  @override
  void initState() {
    super.initState();
    _maybeUpdateData();
    _maybeResumeTrip();
    _refreshActiveTrip();
    _loadFavorites();
    // Refresca el aviso al volver a la app (p. ej. tras detener/llegar).
    _lifecycle = _LifecycleHook(_refreshActiveTrip);
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  /// Si quedó un viaje activo pero el servicio no está corriendo (el sistema lo
  /// mató, o se cerró la app), ofrece reanudar el seguimiento.
  Future<void> _maybeResumeTrip() async {
    if (!await AlarmService.hasActiveTrip()) return;
    if (await AlarmService.isRunning) return;
    final TripPlan? plan = await AlarmService.savedPlan();
    if (plan == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      content: Text('Tenías una alarma activa hacia ${plan.destination.name}.'),
      action: SnackBarAction(
        label: 'Reanudar',
        onPressed: () async {
          await AlarmService.resume();
          if (mounted) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TrackingPage(plan: plan),
            ));
          }
        },
      ),
    ));
  }

  /// Al abrir: comprueba (ligero) si hay datos nuevos y decide según la red y la
  /// preferencia del usuario. En WiFi (o si permite datos móviles) descarga sola;
  /// con datos móviles y preferencia solo-WiFi, pregunta mostrando el tamaño.
  Future<void> _maybeUpdateData() async {
    await _updater.ensureInstalled();
    final force = await _updater.isExpiringSoon();
    final check = await _updater.checkForUpdate(force: force);
    if (!mounted || !check.available || check.remote == null) return;

    final wifiOnly = await _updater.wifiOnly();
    if (check.onWifi || !wifiOnly) {
      final r = await _updater.downloadAndApply(check.remote!);
      if (mounted && r == UpdateResult.updated) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Datos actualizados. Se aplicarán al reiniciar la app.'),
        ));
      }
    } else {
      if (mounted) await showUpdatePrompt(context, _updater, check);
    }
  }

  TripPlan? _activeTrip;

  /// Comprueba si hay una alarma activa para mostrar el aviso de "Detener".
  Future<void> _refreshActiveTrip() async {
    final active = await AlarmService.hasActiveTrip();
    final plan = active ? await AlarmService.savedPlan() : null;
    if (mounted) setState(() => _activeTrip = plan);
  }

  Future<void> _stopActiveTrip() async {
    await AlarmService.stop();
    await _refreshActiveTrip();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarma detenida.')),
      );
    }
  }

  Future<void> _search(String q) async {
    // Al vaciar o dejar 1 carácter, limpia resultados y vuelven las favoritas.
    if (q.trim().length < 2) {
      if (_stops.isNotEmpty) setState(() => _stops = const []);
      return;
    }
    final r = await _db.searchStops(q.trim());
    if (mounted) setState(() => _stops = r);
  }

  Future<void> _loadFavorites() async {
    final f = await Favorites.list();
    if (mounted) setState(() => _favs = f);
  }

  Future<void> _toggleFavorite() async {
    final id = _selected;
    if (id == null) return;
    var row = _selectedRow;
    row ??= await _db.stopById(id);
    if (row == null) return;
    final now = await Favorites.toggle(FavStop(
      id,
      row['name'] as String,
      (row['lat'] as num).toDouble(),
      (row['lon'] as num).toDouble(),
    ));
    await _loadFavorites();
    if (mounted) setState(() => _selectedIsFav = now);
  }

  Future<void> _loadSchedule(int stopId) async {
    final s = await _db.scheduleAtStop(stopId, DateTime.now());
    if (mounted) setState(() => _schedule = s);
  }

  Future<void> _loadArrivals(int stopId, {Map<String, Object?>? row}) async {
    _refreshActiveTrip(); // mantiene el aviso de alarma activa al día
    final fav = await Favorites.isFavorite(stopId);
    setState(() {
      _selected = stopId;
      _selectedRow = row;
      _selectedIsFav = fav;
      _error = null;
      _arrivals = const [];
      _schedule = const [];
    });
    _loadSchedule(stopId); // horario teórico en paralelo (offline)
    try {
      final a = await _rt.arrivals(stopId);
      setState(() => _arrivals = a);
    } catch (e) {
      setState(() => _error = 'No se pudo cargar el tiempo real: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bájate Aquí'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsPage(updater: _updater),
            )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MapPage(db: _db),
        )),
        icon: const Icon(Icons.map),
        label: const Text('Mapa'),
      ),
      body: Column(
        children: [
          if (_activeTrip != null) _activeTripBanner(_activeTrip!),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar parada o código',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          if (_selected == null)
            Expanded(
              child: _stops.isEmpty
                  ? _homeView()
                  : ListView.builder(
                      itemCount: _stops.length,
                      itemBuilder: (_, i) {
                        final s = _stops[i];
                        return ListTile(
                          leading: const Icon(Icons.directions_bus),
                          title: Text(s['name'] as String),
                          subtitle: Text('Parada ${s['stop_id']}'),
                          onTap: () =>
                              _loadArrivals(s['stop_id'] as int, row: s),
                        );
                      },
                    ),
            )
          else
            Expanded(child: _arrivalsView()),
        ],
      ),
    );
  }

  Widget _homeView() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        // Qué se puede hacer (las funciones viven dentro de una parada/viaje).
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Busca tu parada para empezar',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text(
                      'Escribe el nombre o el código de la parada (arriba), o usa '
                      'el botón Mapa. Al abrir una parada podrás:'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _FeatureChip(Icons.wifi, 'Llegadas en tiempo real'),
                      _FeatureChip(Icons.schedule, 'Horario sin conexión'),
                      _FeatureChip(Icons.nightlight_round, 'Última guagua del día'),
                      _FeatureChip(Icons.notifications_active, 'Alarma de bajada'),
                      _FeatureChip(Icons.star, 'Guardar en favoritas'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                      'Durante el viaje también puedes «avisar a alguien» por '
                      'WhatsApp/SMS.',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('Tus paradas favoritas',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (_favs.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
                'Aún no tienes favoritas. Abre una parada y toca la estrella ⭐ '
                'para guardarla aquí.',
                style: TextStyle(color: Colors.grey)),
          )
        else
          for (final f in _favs)
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: Text(f.name),
              subtitle: Text('Parada ${f.id}'),
              onTap: () => _loadArrivals(f.id,
                  row: {'stop_id': f.id, 'name': f.name, 'lat': f.lat, 'lon': f.lon}),
            ),
      ],
    );
  }

  Widget _activeTripBanner(TripPlan plan) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.notifications_active),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Alarma activa hacia ${plan.destination.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () async {
                await AlarmService.resume();
                if (mounted) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TrackingPage(plan: plan),
                  ));
                }
              },
              child: const Text('Ver'),
            ),
            TextButton(
              onPressed: _stopActiveTrip,
              child: const Text('Detener'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _arrivalsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Paradas'),
              ),
              const Spacer(),
              IconButton(
                tooltip: _selectedIsFav ? 'Quitar de favoritas' : 'Añadir a favoritas',
                onPressed: _toggleFavorite,
                icon: Icon(_selectedIsFav ? Icons.star : Icons.star_border,
                    color: _selectedIsFav ? Colors.amber : null),
              ),
              TextButton.icon(
                onPressed: () => chooseLineForAlarm(context, _db, _selected!),
                icon: const Icon(Icons.notifications_active),
                label: const Text('Alarma'),
              ),
              IconButton(
                onPressed: () => _loadArrivals(_selected!),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Tiempo real'), icon: Icon(Icons.wifi)),
              ButtonSegment(value: true, label: Text('Horario'), icon: Icon(Icons.schedule)),
            ],
            selected: {_showSchedule},
            onSelectionChanged: (s) => setState(() => _showSchedule = s.first),
          ),
        ),
        if (_error != null && !_showSchedule)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _showSchedule ? _scheduleList() : _realtimeList(),
        ),
      ],
    );
  }

  Widget _realtimeList() => ListView(
        children: [
          if (_arrivals.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Toca una línea para crear su alarma de bajada.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          for (final a in _arrivals)
            ListTile(
              leading: CircleAvatar(child: Text('${a.lineId}')),
              title: Text(a.lineDestination),
              trailing: Text('${a.minutesLeft} min',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              onTap: () =>
                  chooseLineForAlarm(context, _db, _selected!, onlyLine: a.lineId),
            ),
          if (_arrivals.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Sin llegadas próximas.')),
            ),
          if (_arrivals.isEmpty && _error != null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin tiempo real. Prueba la pestaña "Horario".',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ),
        ],
      );

  Future<void> _showLastDepartures() async {
    final id = _selected;
    if (id == null) return;
    final last = await _db.lastDeparturesAtStop(id, DateTime.now());
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
                    color: s.minutes < 0 ? Colors.red : null,
                  ),
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

  Widget _scheduleList() => ListView(
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
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              onTap: () => chooseLineForAlarm(context, _db, _selected!,
                  onlyLine: int.tryParse(s.lineName)),
            ),
          if (_schedule.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay más salidas programadas hoy.')),
            ),
        ],
      );

  late final _LifecycleHook _lifecycle;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    _rt.dispose();
    super.dispose();
  }
}

/// Etiqueta con icono para explicar una función en la pantalla de inicio.
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip(this.icon, this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Observa cuándo la app vuelve a primer plano para refrescar el estado.
class _LifecycleHook extends WidgetsBindingObserver {
  final void Function() onResumed;
  _LifecycleHook(this.onResumed);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
