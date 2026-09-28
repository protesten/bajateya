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

/// Resultado de proyectar un punto sobre el trazado.
class ShapeProjection {
  final double progress; // distancia (m) recorrida a lo largo del trazado
  final double offset; // distancia (m) perpendicular del punto al trazado
  const ShapeProjection(this.progress, this.offset);
}

/// Proyecta [p] sobre la polilínea y devuelve solo la distancia recorrida (m).
/// Utilidad para el preprocesado de datos (mide paradas a lo largo del trazado).
double distanceAlongShape(List<LatLng> shape, LatLng p, {double minProgress = 0}) {
  final proj = projectOnShape(shape, p, minProgress: minProgress, window: double.infinity);
  return math.max(minProgress, proj.progress);
}

/// Proyecta [p] sobre la polilínea restringiendo la búsqueda a una VENTANA
/// alrededor de [minProgress]: acepta segmentos cuyo avance esté en
/// [minProgress - backTol, minProgress + window]. Así, en trazados que se
/// cruzan, circulares o con ramales compartidos, no "salta" a un tramo lejano.
/// Devuelve el avance y el desvío perpendicular (para detectar fuera de ruta).
ShapeProjection projectOnShape(
  List<LatLng> shape,
  LatLng p, {
  double minProgress = 0,
  double window = 600,
  double backTol = 80,
}) {
  if (shape.length < 2) return ShapeProjection(minProgress, 0);
  final lo = minProgress - backTol;
  final hi = minProgress + window;
  double bestDist = double.infinity;
  double bestProgress = minProgress;
  double acc = 0;
  bool foundInWindow = false;
  for (var i = 0; i < shape.length - 1; i++) {
    final a = shape[i], b = shape[i + 1];
    final segLen = haversineMeters(a, b);
    final segEnd = acc + segLen;
    // Descarta segmentos fuera de la ventana (salvo que aún no haya candidato).
    final inWindow = segEnd >= lo && acc <= hi;
    if (inWindow || !foundInWindow) {
      final t = _projectOnSegment(p, a, b);
      final foot =
          LatLng(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
      final d = haversineMeters(p, foot);
      final prog = acc + segLen * t;
      if (inWindow) {
        if (!foundInWindow || d < bestDist) {
          bestDist = d;
          bestProgress = prog;
          foundInWindow = true;
        }
      } else if (!foundInWindow && d < bestDist) {
        bestDist = d;
        bestProgress = prog;
      }
    }
    acc = segEnd;
  }
  return ShapeProjection(bestProgress, bestDist);
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
  final int? etaSeconds; // null si el ETA no es fiable
  final bool shouldRing;
  final bool arrived;

  /// La posición está lejos del trazado (sentido equivocado, otra guagua,
  /// desvío o error de proyección): las cuentas de paradas/metros no son fiables.
  final bool offRoute;

  const AlarmStatus({
    required this.stopsRemaining,
    required this.metersRemaining,
    required this.etaSeconds,
    required this.shouldRing,
    required this.arrived,
    required this.offRoute,
  });
}

/// Motor de la alarma de bajada.
///
/// Sigue la posición GPS proyectándola sobre el trazado del trayecto, calcula
/// paradas y distancia que faltan hasta la parada de destino y decide cuándo
/// avisar. Funciona sin conexión (solo GPS + datos GTFS locales).
///
/// Diseño defensivo: siempre sesga a avisar de más, nunca de menos.
/// - Dispara con la primera condición que se cumpla (paradas / metros / minutos).
/// - Red de seguridad geodésica: avisa al entrar en [safetyRadius] del destino,
///   aunque el map matching falle.
/// - Fuera de ruta: no avanza el progreso (no se fía), pero mantiene la red de
///   seguridad por distancia directa al destino.
class GetOffAlarm {
  final List<TripStop> stops; // ordenadas por distFromStart
  final int destIndex; // índice de la parada de bajada en [stops]
  final List<LatLng> shape; // polilínea del trazado (para proyectar la posición)
  final AlarmConfig config;

  /// Radio (m) alrededor del destino que dispara la alarma como red de seguridad.
  final double safetyRadius;

  /// Desvío (m) del trazado por encima del cual se considera "fuera de ruta".
  final double offRouteThreshold;

  double _lastProgress = 0; // distancia (m) recorrida sobre el trazado
  double? _speed; // m/s suavizado
  DateTime? _lastTime;
  int _speedSamples = 0;
  bool _rang = false;

  GetOffAlarm({
    required this.stops,
    required this.destIndex,
    required this.shape,
    required this.config,
    this.safetyRadius = 120,
    this.offRouteThreshold = 150,
  });

  double get _destDist => stops[destIndex].distFromStart;
  LatLng get _destPos => stops[destIndex].pos;

  /// Alimenta una nueva medición de posición y devuelve el estado.
  ///
  /// [accuracy] es la precisión estimada del GPS (m), si se conoce: cuanto peor,
  /// más se ensancha el umbral de fuera de ruta y antes actúa la red de seguridad.
  AlarmStatus update(LatLng pos, DateTime now, {double accuracy = 0}) {
    // Primer fix: localiza en TODO el trazado (el usuario puede subir a mitad
    // de trayecto). Después, ventana alrededor del progreso previo.
    final proj = _lastTime == null
        ? projectOnShape(shape, pos, minProgress: 0, window: double.infinity)
        : projectOnShape(shape, pos, minProgress: _lastProgress);
    final offRoute = proj.offset > (offRouteThreshold + accuracy);
    if (_lastTime == null && !offRoute) _lastProgress = proj.progress;

    // Solo avanzamos el progreso y estimamos velocidad si estamos EN ruta.
    if (!offRoute) {
      final progress = math.max(_lastProgress, proj.progress);
      if (_lastTime != null) {
        final dt = now.difference(_lastTime!).inMilliseconds / 1000.0;
        if (dt > 0.5) {
          final v = (progress - _lastProgress) / dt;
          if (v.isFinite && v >= 0) {
            _speed = _speed == null ? v : 0.6 * _speed! + 0.4 * v;
            _speedSamples++;
          }
        }
      }
      _lastProgress = progress;
      _lastTime = now;
    }

    final metersRemaining = math.max(0.0, _destDist - _lastProgress);
    final stopsRemaining = _stopsRemaining(_lastProgress);
    final geodesicToDest = haversineMeters(pos, _destPos);

    // ETA solo fiable con velocidad razonable y varias muestras (evita que un
    // atasco/semáforo infle el ETA y retrase un aviso por tiempo).
    final etaReliable = _speed != null && _speed! > 0.8 && _speedSamples >= 3;
    final eta = etaReliable ? (metersRemaining / _speed!).round() : null;

    // Llegada: por progreso sobre el trazado o por cercanía directa (red de
    // seguridad que funciona incluso fuera de ruta).
    final arrived =
        (!offRoute && metersRemaining < 40) || geodesicToDest < (40 + accuracy);

    final safetyNet = geodesicToDest <= (safetyRadius + accuracy);
    final triggered = !offRoute &&
        _triggerReached(stopsRemaining, metersRemaining, eta);

    final shouldRing = !_rang && (arrived || safetyNet || triggered);
    if (shouldRing) _rang = true;

    return AlarmStatus(
      stopsRemaining: stopsRemaining,
      metersRemaining: metersRemaining,
      etaSeconds: eta,
      shouldRing: shouldRing,
      arrived: arrived,
      offRoute: offRoute,
    );
  }

  /// Evaluación sin nuevo fix de GPS (túnel / sombra): avanza la posición con
  /// "dead reckoning" según la última velocidad conocida y comprueba si, según
  /// esa estimación, ya tocaría avisar. Solo dispara la red de seguridad por
  /// llegada estimada; nunca inventa un "fuera de ruta".
  AlarmStatus? predictWithoutFix(DateTime now, {double maxSeconds = 90}) {
    if (_rang || _lastTime == null || _speed == null) return null;
    final dt = now.difference(_lastTime!).inMilliseconds / 1000.0;
    if (dt <= 0 || dt > maxSeconds) return null;

    final predicted = _lastProgress + _speed! * dt;
    final metersRemaining = math.max(0.0, _destDist - predicted);
    final stopsRemaining = _stopsRemaining(predicted);
    final arrivedEst = metersRemaining < 40;
    final triggered = _triggerReached(stopsRemaining, metersRemaining, null);
    if (arrivedEst || triggered) {
      _rang = true;
      return AlarmStatus(
        stopsRemaining: stopsRemaining,
        metersRemaining: metersRemaining,
        etaSeconds: null,
        shouldRing: true,
        arrived: arrivedEst,
        offRoute: false,
      );
    }
    return null;
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
}
