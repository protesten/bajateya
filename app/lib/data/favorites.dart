import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una parada favorita guardada en el dispositivo (sin registro).
class FavStop {
  final int id;
  final String name;
  final double lat, lon;
  const FavStop(this.id, this.name, this.lat, this.lon);

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'lat': lat, 'lon': lon};

  static FavStop fromJson(Map<String, Object?> j) => FavStop(
        j['id'] as int,
        j['name'] as String,
        (j['lat'] as num).toDouble(),
        (j['lon'] as num).toDouble(),
      );
}

/// Gestión de paradas favoritas en `SharedPreferences`. Local, sin cuenta.
class Favorites {
  static const _key = 'fav_stops';

  /// Se incrementa cada vez que cambian los favoritos (para refrescar la UI).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static void _bump() => revision.value++;

  static Future<List<FavStop>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => FavStop.fromJson((e as Map).cast<String, Object?>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isFavorite(int stopId) async =>
      (await list()).any((f) => f.id == stopId);

  static Future<void> _save(List<FavStop> stops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(stops.map((f) => f.toJson()).toList()));
  }

  static Future<void> add(FavStop stop) async {
    final stops = await list();
    if (stops.any((f) => f.id == stop.id)) return;
    stops.add(stop);
    await _save(stops);
    _bump();
  }

  static Future<void> remove(int stopId) async {
    final stops = await list()..removeWhere((f) => f.id == stopId);
    await _save(stops);
    _bump();
  }

  /// Alterna el favorito y devuelve el nuevo estado (true = ahora es favorita).
  static Future<bool> toggle(FavStop stop) async {
    if (await isFavorite(stop.id)) {
      await remove(stop.id);
      return false;
    }
    await add(stop);
    return true;
  }

  /// Exporta los favoritos como texto JSON (para copiar/guardar).
  static Future<String> export() async =>
      jsonEncode((await list()).map((f) => f.toJson()).toList());

  /// Importa desde JSON, fusionando con los existentes. Devuelve cuántos añadió.
  static Future<int> import(String jsonText) async {
    final arr = jsonDecode(jsonText) as List;
    final incoming = arr
        .map((e) => FavStop.fromJson((e as Map).cast<String, Object?>()))
        .toList();
    final current = await list();
    final ids = current.map((f) => f.id).toSet();
    var added = 0;
    for (final f in incoming) {
      if (ids.add(f.id)) {
        current.add(f);
        added++;
      }
    }
    await _save(current);
    if (added > 0) _bump();
    return added;
  }
}
