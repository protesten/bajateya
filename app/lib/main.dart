import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'alarm/alarm_service.dart';
import 'alarm/trip_plan.dart';
import 'data/data_updater.dart';
import 'data/favorites.dart';
import 'data/gtfs_db.dart';
import 'data/titsa_realtime.dart';
import 'ui/data_update_ui.dart';
import 'ui/help_page.dart';
import 'ui/map_page.dart';
import 'ui/settings_page.dart';
import 'ui/stop_detail_page.dart';
import 'ui/tracking_page.dart';

/// Clave SAE inyectada en compilación:  --dart-define=TITSA_ID_APP=xxxx
const String kIdApp = String.fromEnvironment('TITSA_ID_APP');

/// URL del manifest de datos (release "gtfs" del repositorio en GitHub).
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
      home: const RootPage(),
    );
  }
}

/// Contenedor principal con menú inferior: Inicio · Favoritas · Mapa · Ajustes.
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  final _db = GtfsDb();
  final _rt = TitsaRealtime(idApp: kIdApp);
  final _updater =
      DataUpdater(manifestUrl: kManifestUrl, appVersion: kAppVersion);

  int _index = 0;
  TripPlan? _activeTrip;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlarmService.tripRevision.addListener(_refreshActiveTrip);
    _maybeUpdateData();
    _maybeResumeTrip();
    _refreshActiveTrip();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmService.tripRevision.removeListener(_refreshActiveTrip);
    _rt.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshActiveTrip();
  }

  Future<void> _refreshActiveTrip() async {
    final active = await AlarmService.hasActiveTrip();
    final plan = active ? await AlarmService.savedPlan() : null;
    if (mounted) setState(() => _activeTrip = plan);
  }

  Future<void> _maybeResumeTrip() async {
    if (!await AlarmService.hasActiveTrip()) return;
    if (await AlarmService.isRunning) return;
    final plan = await AlarmService.savedPlan();
    if (plan == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      content: Text('Tenías una alarma activa hacia ${plan.destination.name}.'),
      action: SnackBarAction(
        label: 'Reanudar',
        onPressed: () => _openTracking(plan),
      ),
    ));
  }

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
          content: Text('Datos actualizados. Se aplicarán al reiniciar la app.'),
        ));
      }
    } else if (mounted) {
      await showUpdatePrompt(context, _updater, check);
    }
  }

  Future<void> _openTracking(TripPlan plan) async {
    await AlarmService.resume();
    if (mounted) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TrackingPage(plan: plan)));
    }
  }

  Future<void> _stopActiveTrip() async {
    await AlarmService.stop();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Alarma detenida.')));
    }
  }

  void _openStop(int stopId, {Map<String, Object?>? row}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StopDetailPage(
          db: _db, rt: _rt, stopId: stopId, initialRow: row),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(db: _db, onOpenStop: _openStop),
      FavoritesTab(onOpenStop: _openStop),
      MapPage(db: _db, onOpenStop: _openStop),
      SettingsPage(updater: _updater),
    ];

    return Scaffold(
      body: Column(
        children: [
          if (_activeTrip != null) _activeTripBanner(_activeTrip!),
          Expanded(child: IndexedStack(index: _index, children: tabs)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.star_outline), selectedIcon: Icon(Icons.star), label: 'Favoritas'),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Mapa'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }

  Widget _activeTripBanner(TripPlan plan) {
    return SafeArea(
      bottom: false,
      child: Material(
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
              TextButton(onPressed: () => _openTracking(plan), child: const Text('Ver')),
              TextButton(onPressed: _stopActiveTrip, child: const Text('Detener')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pestaña Inicio: buscar parada + tarjeta de bienvenida + favoritas rápidas.
class HomeTab extends StatefulWidget {
  final GtfsDb db;
  final void Function(int stopId, {Map<String, Object?>? row}) onOpenStop;
  const HomeTab({super.key, required this.db, required this.onOpenStop});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, Object?>> _stops = const [];
  List<FavStop> _favs = const [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    Favorites.revision.addListener(_loadFavorites);
  }

  @override
  void dispose() {
    Favorites.revision.removeListener(_loadFavorites);
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final f = await Favorites.list();
    if (mounted) setState(() => _favs = f);
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      if (_stops.isNotEmpty) setState(() => _stops = const []);
      return;
    }
    final r = await widget.db.searchStops(q.trim());
    if (mounted) setState(() => _stops = r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bájate Aquí'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Ayuda',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpPage())),
          ),
        ],
      ),
      body: Column(
        children: [
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
          Expanded(
            child: _stops.isEmpty
                ? _welcome()
                : ListView.builder(
                    itemCount: _stops.length,
                    itemBuilder: (_, i) {
                      final s = _stops[i];
                      return ListTile(
                        leading: const Icon(Icons.directions_bus),
                        title: Text(s['name'] as String),
                        subtitle: Text('Parada ${s['stop_id']}'),
                        onTap: () =>
                            widget.onOpenStop(s['stop_id'] as int, row: s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
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
                  const Text('Escribe el nombre o el código de la parada, o usa la '
                      'pestaña Mapa. Al abrir una parada podrás:'),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HelpPage())),
                      icon: const Icon(Icons.help_outline, size: 18),
                      label: const Text('Cómo funciona la app'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_favs.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text('Tus paradas favoritas',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final f in _favs)
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: Text(f.name),
              subtitle: Text('Parada ${f.id}'),
              onTap: () => widget.onOpenStop(f.id, row: {
                'stop_id': f.id,
                'name': f.name,
                'lat': f.lat,
                'lon': f.lon
              }),
            ),
        ],
      ],
    );
  }
}

/// Pestaña Favoritas: lista completa con gestión.
class FavoritesTab extends StatefulWidget {
  final void Function(int stopId, {Map<String, Object?>? row}) onOpenStop;
  const FavoritesTab({super.key, required this.onOpenStop});

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  List<FavStop> _favs = const [];

  @override
  void initState() {
    super.initState();
    _load();
    Favorites.revision.addListener(_load);
  }

  @override
  void dispose() {
    Favorites.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final f = await Favorites.list();
    if (mounted) setState(() => _favs = f);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritas')),
      body: _favs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no tienes paradas favoritas.\n\nAbre una parada y toca la '
                  'estrella ⭐ para guardarla aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView(
              children: [
                for (final f in _favs)
                  Dismissible(
                    key: ValueKey(f.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => Favorites.remove(f.id),
                    child: ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(f.name),
                      subtitle: Text('Parada ${f.id}'),
                      onTap: () => widget.onOpenStop(f.id, row: {
                        'stop_id': f.id,
                        'name': f.name,
                        'lat': f.lat,
                        'lon': f.lon
                      }),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Desliza una parada a la izquierda para quitarla.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
    );
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
