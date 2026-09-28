import 'dart:math' as math;

/// Un punto geográfico simple.
class LatLng {
  final double lat, lon;
  const LatLng(this.lat, this.lon);
}

/// Distancia haversine (m) entre dos puntos.
double haversineMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180.0;
  final dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
}

/// Proyecta [p] sobre la polilínea [shape] y devuelve la distancia (m)
/// recorrida a lo largo del trazado hasta el punto proyectado más cercano.
/// Si [minProgress] se indica, no devuelve un valor menor (evita retrocesos por
/// ruido del GPS).
double distanceAlongShape(List<LatLng> shape, LatLng p, {double minProgress = 0}) {
  if (shape.length < 2) return minProgress;
  double bestDist = double.infinity;
  double bestProgress = minProgress;
  double acc = 0;
  for (var i = 0; i < shape.length - 1; i++) {
    final a = shape[i], b = shape[i + 1];
    final segLen = haversineMeters(a, b);
    final t = _projectOnSegment(p, a, b);
    final foot = LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    final d = haversineMeters(p, foot);
    if (d < bestDist) {
      bestDist = d;
      bestProgress = acc + segLen * t;
    }
    acc += segLen;
  }
  return math.max(minProgress, bestProgress);
}

double _projectOnSegment(LatLng p, LatLng a, LatLng b) {
  final dx = b.lon - a.lon, dy = b.lat - a.lat;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return 0;
  final t = ((p.lon - a.lon) * dx + (p.lat - a.lat) * dy) / len2;
  return t.clamp(0.0, 1.0);
}

/// Una parada del trayecto que el usuario está siguiendo, en orden.
class TripStop {
  final int stopId;
  final String name;
  final LatLng pos;

  /// Distancia acumulada (m) desde el inicio del trayecto hasta esta parada,
  /// medida sobre el trazado real de la línea (no en línea recta).
  final double distFromStart;

  const TripStop({
    required this.stopId,
    required this.name,
    required this.pos,
    required this.distFromStart,
  });
}

/// Cómo se dispara la alarma.
enum TriggerKind { stopsBefore, metersBefore, minutesBefore }

class AlarmConfig {
  final TriggerKind kind;
  final int value; // nº de paradas, metros, o minutos según [kind]
  const AlarmConfig.stopsBefore(this.value) : kind = TriggerKind.stopsBefore;
  const AlarmConfig.metersBefore(this.value) : kind = TriggerKind.metersBefore;
  const AlarmConfig.minutesBefore(this.value) : kind = TriggerKind.minutesBefore;
}

/// Estado que la UI/servicio muestran en cada actualización de posición.
class AlarmStatus {
  final int stopsRemaining;
  final double metersRemaining;
  final int? etaSeconds; // null si aún no hay velocidad estimada
  final bool shouldRing;
  final bool arrived;

  const AlarmStatus({
    required this.stopsRemaining,
    required this.metersRemaining,
    required this.etaSeconds,
    required this.shouldRing,
    required this.arrived,
  });
}

/// Motor de la alarma de bajada.
///
/// Sigue la posición GPS proyectándola sobre el trazado del trayecto, calcula
/// paradas y distancia que faltan hasta la parada de destino y decide cuándo
/// avisar. Funciona sin conexión (solo GPS + datos GTFS locales).
class GetOffAlarm {
  final List<TripStop> stops; // ordenadas por distFromStart
  final int destIndex; // índice de la parada de bajada en [stops]
  final List<LatLng> shape; // polilínea del trazado (para proyectar la posición)
  final AlarmConfig config;

  double _lastProgress = 0; // distancia (m) recorrida sobre el trazado
  double? _speed; // m/s suavizado
  DateTime? _lastTime;
  bool _rang = false;

  GetOffAlarm({
    required this.stops,
    required this.destIndex,
    required this.shape,
    required this.config,
  });

  double get _destDist => stops[destIndex].distFromStart;

  /// Alimenta una nueva medición de posición y devuelve el estado.
  AlarmStatus update(LatLng pos, DateTime now) {
    final progress = _projectOntoShape(pos);

    // Velocidad suavizada (EMA) para el ETA.
    if (_lastTime != null) {
      final dt = now.difference(_lastTime!).inMilliseconds / 1000.0;
      if (dt > 0.5) {
        final v = (progress - _lastProgress) / dt;
        if (v.isFinite && v >= 0) {
          _speed = _speed == null ? v : 0.6 * _speed! + 0.4 * v;
        }
        _lastProgress = progress;
        _lastTime = now;
      }
    } else {
      _lastProgress = progress;
      _lastTime = now;
    }

    final metersRemaining = math.max(0.0, _destDist - progress);
    final stopsRemaining = _stopsRemaining(progress);
    final eta = (_speed != null && _speed! > 0.3)
        ? (metersRemaining / _speed!).round()
        : null;

    final arrived = metersRemaining < 40; // ~40 m: prácticamente en la parada
    final shouldRing = !_rang && (arrived || _triggerReached(stopsRemaining, metersRemaining, eta));
    if (shouldRing) _rang = true;

    return AlarmStatus(
      stopsRemaining: stopsRemaining,
      metersRemaining: metersRemaining,
      etaSeconds: eta,
      shouldRing: shouldRing,
      arrived: arrived,
    );
  }

  bool _triggerReached(int stopsRem, double metersRem, int? eta) {
    switch (config.kind) {
      case TriggerKind.stopsBefore:
        return stopsRem <= config.value;
      case TriggerKind.metersBefore:
        return metersRem <= config.value;
      case TriggerKind.minutesBefore:
        return eta != null && eta <= config.value * 60;
    }
  }

  int _stopsRemaining(double progress) {
    var count = 0;
    for (var i = 0; i <= destIndex; i++) {
      // Paradas cuyo punto sobre el trazado aún no hemos pasado.
      if (stops[i].distFromStart > progress + 15) count++;
    }
    return count;
  }

  /// Proyecta la posición sobre el trazado y devuelve la distancia recorrida (m).
  double _projectOntoShape(LatLng p) =>
      distanceAlongShape(shape, p, minProgress: _lastProgress);
}
