import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/gtfs_db.dart';
import 'alarm_entry.dart';

/// Mapa de paradas: muestra las paradas del área visible y la ubicación del
/// usuario. Al tocar una parada, ofrece crear una alarma de bajada.
class MapPage extends StatefulWidget {
  final GtfsDb db;
  const MapPage({super.key, required this.db});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  List<Map<String, Object?>> _stops = const [];
  LatLng? _me;
  bool _loading = false;

  // Centro por defecto: Santa Cruz de Tenerife.
  static const _fallback = LatLng(28.4636, -16.2518);

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _me = LatLng(pos.latitude, pos.longitude));
      _map.move(_me!, 15);
    } catch (_) {
      // Sin ubicación: se queda en el centro por defecto.
    }
  }

  Future<void> _loadVisibleStops() async {
    final b = _map.camera.visibleBounds;
    // Evita cargar demasiadas paradas con el mapa muy alejado.
    if (_map.camera.zoom < 13) {
      if (_stops.isNotEmpty) setState(() => _stops = const []);
      return;
    }
    setState(() => _loading = true);
    final rows = await widget.db.stopsInBounds(
      b.south, b.north, b.west, b.east,
    );
    if (!mounted) return;
    setState(() {
      _stops = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de paradas'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _me == null ? _locate() : _map.move(_me!, 16),
        child: const Icon(Icons.my_location),
      ),
      body: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: _fallback,
          initialZoom: 13,
          onMapReady: _loadVisibleStops,
          onPositionChanged: (pos, hasGesture) {
            if (hasGesture) _loadVisibleStops();
          },
          minZoom: 8,
          maxZoom: 18,
        ),
        children: [
          TileLayer(
            urlTemplate: osmTileUrl,
            userAgentPackageName: tileUserAgentPackage,
            maxZoom: 19,
          ),
          if (_me != null)
            MarkerLayer(markers: [
              Marker(
                point: _me!,
                width: 22,
                height: 22,
                child: const _MeDot(),
              ),
            ]),
          MarkerLayer(
            markers: [
              for (final s in _stops)
                Marker(
                  point: LatLng(s['lat'] as double, s['lon'] as double),
                  width: 34,
                  height: 34,
                  child: GestureDetector(
                    onTap: () => _onStopTap(s),
                    child: const Icon(Icons.directions_bus,
                        color: Color(0xFF2E7D32), size: 28),
                  ),
                ),
            ],
          ),
          const _OsmAttribution(),
        ],
      ),
    );
  }

  void _onStopTap(Map<String, Object?> s) {
    final id = s['stop_id'] as int;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_bus),
              title: Text(s['name'] as String),
              subtitle: Text('Parada $id'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_active),
              title: const Text('Crear alarma de bajada'),
              onTap: () {
                Navigator.of(context).pop();
                chooseLineForAlarm(context, widget.db, id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      );
}

/// Atribución obligatoria de OpenStreetMap.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          color: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: const Text('© OpenStreetMap',
              style: TextStyle(fontSize: 10, color: Colors.black)),
        ),
      );
}
