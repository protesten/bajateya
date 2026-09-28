import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'alarm/alarm_service.dart';
import 'data/data_updater.dart';
import 'data/gtfs_db.dart';
import 'data/titsa_realtime.dart';
import 'alarm/trip_plan.dart';
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
  String? _error;
  final _updater =
      DataUpdater(manifestUrl: kManifestUrl, appVersion: kAppVersion);

  @override
  void initState() {
    super.initState();
    _maybeUpdateData();
    _maybeResumeTrip();
    _refreshActiveTrip();
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
    if (q.trim().length < 2) return;
    final r = await _db.searchStops(q.trim());
    setState(() => _stops = r);
  }

  Future<void> _loadArrivals(int stopId) async {
    _refreshActiveTrip(); // mantiene el aviso de alarma activa al día
    setState(() {
      _selected = stopId;
      _error = null;
      _arrivals = const [];
    });
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
              child: ListView.builder(
                itemCount: _stops.length,
                itemBuilder: (_, i) {
                  final s = _stops[i];
                  return ListTile(
                    leading: const Icon(Icons.directions_bus),
                    title: Text(s['name'] as String),
                    subtitle: Text('Parada ${s['stop_id']}'),
                    onTap: () => _loadArrivals(s['stop_id'] as int),
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView(
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
            ],
          ),
        ),
      ],
    );
  }

  late final _LifecycleHook _lifecycle;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    _rt.dispose();
    super.dispose();
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
