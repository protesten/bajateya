import 'dart:convert';

import 'get_off_alarm.dart';

/// Plan de viaje serializable: todo lo que la alarma necesita para seguir el
/// trayecto. Se guarda como JSON para poder pasarlo al isolate del servicio en
/// segundo plano.
class TripPlan {
  final int patternId;
  final String lineName;
  final String headsign;
  final int destIndex;
  final List<TripStop> stops;
  final List<LatLng> shape;
  final AlarmConfig config;

  TripPlan({
    required this.patternId,
    required this.lineName,
    required this.headsign,
    required this.destIndex,
    required this.stops,
    required this.shape,
    required this.config,
  });

  TripStop get destination => stops[destIndex];

  GetOffAlarm buildAlarm() => GetOffAlarm(
        stops: stops,
        destIndex: destIndex,
        shape: shape,
        config: config,
      );

  Map<String, dynamic> toJson() => {
        'patternId': patternId,
        'lineName': lineName,
        'headsign': headsign,
        'destIndex': destIndex,
        'triggerKind': config.kind.index,
        'triggerValue': config.value,
        'stops': stops
            .map((s) => [s.stopId, s.name, s.pos.lat, s.pos.lon, s.distFromStart])
            .toList(),
        'shape': shape.map((p) => [p.lat, p.lon]).toList(),
      };

  String encode() => jsonEncode(toJson());

  static TripPlan decode(String s) => fromJson(jsonDecode(s) as Map<String, dynamic>);

  static TripPlan fromJson(Map<String, dynamic> j) {
    final stops = (j['stops'] as List).map((e) {
      final l = e as List;
      return TripStop(
        stopId: l[0] as int,
        name: l[1] as String,
        pos: LatLng((l[2] as num).toDouble(), (l[3] as num).toDouble()),
        distFromStart: (l[4] as num).toDouble(),
      );
    }).toList();
    final shape = (j['shape'] as List).map((e) {
      final l = e as List;
      return LatLng((l[0] as num).toDouble(), (l[1] as num).toDouble());
    }).toList();

    final kind = TriggerKind.values[j['triggerKind'] as int];
    final value = j['triggerValue'] as int;
    final config = switch (kind) {
      TriggerKind.stopsBefore => AlarmConfig.stopsBefore(value),
      TriggerKind.metersBefore => AlarmConfig.metersBefore(value),
      TriggerKind.minutesBefore => AlarmConfig.minutesBefore(value),
    };

    return TripPlan(
      patternId: j['patternId'] as int,
      lineName: j['lineName'] as String,
      headsign: j['headsign'] as String,
      destIndex: j['destIndex'] as int,
      stops: stops,
      shape: shape,
      config: config,
    );
  }
}
