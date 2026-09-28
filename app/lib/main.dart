import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'alarm/alarm_service.dart';
import 'data/data_updater.dart';
import 'data/gtfs_db.dart';
import 'data/titsa_realtime.dart';
import 'ui/alarm_entry.dart';
import 'ui/data_update_ui.dart';
import 'ui/map_page.dart';
import 'ui/settings_page.dart';

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

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return;
    final r = await _db.searchStops(q.trim());
    setState(() => _stops = r);
  }

  Future<void> _loadArrivals(int stopId) async {
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar parada',
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
              for (final a in _arrivals)
                ListTile(
                  leading: CircleAvatar(child: Text('${a.lineId}')),
                  title: Text(a.lineDestination),
                  trailing: Text('${a.minutesLeft} min',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
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

  @override
  void dispose() {
    _rt.dispose();
    super.dispose();
  }
}
