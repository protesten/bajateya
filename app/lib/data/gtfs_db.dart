import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;
import 'package:sqflite/sqflite.dart';

import '../alarm/get_off_alarm.dart';

/// Acceso de solo lectura a la base de datos GTFS empaquetada con la app.
class GtfsDb {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'guaguas.sqlite');
    // Copia el asset la primera vez (o si cambia de versión).
    if (!await File(path).exists()) {
      final bytes = await rootBundle.load('assets/guaguas.sqlite');
      await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }
    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  /// Paradas más cercanas a una posición (búsqueda por bounding box + haversine).
  Future<List<Map<String, Object?>>> nearbyStops(double lat, double lon,
      {int limit = 20}) async {
    final db = await _open();
    const dLat = 0.02, dLon = 0.02; // ~2 km
    return db.rawQuery('''
      SELECT stop_id, name, lat, lon
      FROM stops
      WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
      ORDER BY (lat-?)*(lat-?) + (lon-?)*(lon-?)
      LIMIT ?
    ''', [lat - dLat, lat + dLat, lon - dLon, lon + dLon,
          lat, lat, lon, lon, limit]);
  }

  /// Paradas dentro de un rectángulo geográfico (área visible del mapa).
  Future<List<Map<String, Object?>>> stopsInBounds(
      double minLat, double maxLat, double minLon, double maxLon,
      {int limit = 400}) async {
    final db = await _open();
    return db.rawQuery('''
      SELECT stop_id, name, lat, lon FROM stops
      WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?
      LIMIT ?
    ''', [minLat, maxLat, minLon, maxLon, limit]);
  }

  /// Busca paradas por nombre o por **código** (si el texto es numérico).
  Future<List<Map<String, Object?>>> searchStops(String q,
      {int limit = 30}) async {
    final db = await _open();
    final code = int.tryParse(q.trim());
    if (code != null) {
      // Coincidencia por código (exacta primero, luego por prefijo).
      return db.rawQuery('''
        SELECT stop_id, name, lat, lon FROM stops
        WHERE stop_id = ? OR CAST(stop_id AS TEXT) LIKE ?
        ORDER BY (stop_id = ?) DESC, stop_id LIMIT ?
      ''', [code, '$code%', code, limit]);
    }
    return db.rawQuery(
      "SELECT stop_id, name, lat, lon FROM stops WHERE name LIKE ? LIMIT ?",
      ['%${q.toUpperCase()}%', limit],
    );
  }

  /// Líneas (deduplicadas por número + destino) que pasan por una parada.
  /// De cada línea/destino se elige el patrón con **más paradas por delante**
  /// de esta (mejor itinerario para una alarma de bajada).
  Future<List<Map<String, Object?>>> patternsThroughStop(int stopId) async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT ps.seq, p.pattern_id, r.short_name, p.headsign, p.shape_id,
             p.n_stops
      FROM pattern_stops ps
      JOIN patterns p ON p.pattern_id = ps.pattern_id
      JOIN routes  r ON r.route_id   = p.route_id
      WHERE ps.stop_id = ?
    ''', [stopId]);

    // Dedup por (short_name, headsign) quedándonos con el de más paradas
    // posteriores a la de subida.
    final best = <String, Map<String, Object?>>{};
    for (final r in rows) {
      final key = '${r['short_name']}|${r['headsign']}';
      final onward = (r['n_stops'] as int) - 1 - (r['seq'] as int);
      final prev = best[key];
      if (prev == null || onward > (prev['_onward'] as int)) {
        best[key] = {
          'pattern_id': r['pattern_id'],
          'short_name': r['short_name'],
          'headsign': r['headsign'],
          'shape_id': r['shape_id'],
          '_onward': onward,
        };
      }
    }
    final out = best.values.toList()
      ..sort((a, b) {
        final an = int.tryParse('${a['short_name']}') ?? 9999;
        final bn = int.tryParse('${b['short_name']}') ?? 9999;
        return an != bn
            ? an.compareTo(bn)
            : '${a['headsign']}'.compareTo('${b['headsign']}');
      });
    return out;
  }

  /// Puntos del trazado de un patrón (para el mapa y para proyectar el GPS).
  Future<List<LatLng>> shape(String shapeId) async {
    final db = await _open();
    final rows = await db.rawQuery(
      "SELECT lat, lon FROM shape_points WHERE shape_id = ? ORDER BY seq",
      [shapeId],
    );
    return rows
        .map((r) => LatLng(r['lat'] as double, r['lon'] as double))
        .toList();
  }

  /// Paradas ordenadas de un patrón y su trazado. La distancia de cada parada
  /// se mide **a lo largo del trazado** (coherente con la proyección del GPS
  /// en la alarma). Si no hay trazado, cae a distancias en línea recta.
  Future<({List<TripStop> stops, List<LatLng> shape})> patternStopsAndShape(
      int patternId, String? shapeId) async {
    final db = await _open();
    final rows = await db.rawQuery('''
      SELECT ps.seq, ps.stop_id, s.name, s.lat, s.lon
      FROM pattern_stops ps
      JOIN stops s ON s.stop_id = ps.stop_id
      WHERE ps.pattern_id = ?
      ORDER BY ps.seq
    ''', [patternId]);

    final shapePts =
        (shapeId != null && shapeId.isNotEmpty) ? await shape(shapeId) : <LatLng>[];

    final out = <TripStop>[];
    double straightAcc = 0;
    LatLng? prev;
    double lastAlong = 0;
    for (final r in rows) {
      final pos = LatLng(r['lat'] as double, r['lon'] as double);
      double dist;
      if (shapePts.length >= 2) {
        dist = distanceAlongShape(shapePts, pos, minProgress: lastAlong);
        lastAlong = dist;
      } else {
        if (prev != null) straightAcc += haversineMeters(prev, pos);
        dist = straightAcc;
      }
      out.add(TripStop(
        stopId: r['stop_id'] as int,
        name: r['name'] as String,
        pos: pos,
        distFromStart: dist,
      ));
      prev = pos;
    }
    return (stops: out, shape: shapePts);
  }
}
