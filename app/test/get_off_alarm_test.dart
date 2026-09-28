import 'package:flutter_test/flutter_test.dart';
import 'package:bajate_aqui/alarm/get_off_alarm.dart';

void main() {
  // Trayecto recto de 5 paradas separadas ~200 m sobre una línea E-O.
  final stops = <TripStop>[];
  final shape = <LatLng>[];
  const lat0 = 28.45;
  for (var i = 0; i < 5; i++) {
    final lon = -16.30 + i * 0.002; // ~200 m por paso a esta latitud
    stops.add(TripStop(
      stopId: 1000 + i,
      name: 'Parada $i',
      pos: LatLng(lat0, lon),
      distFromStart: i * 200.0,
    ));
  }
  // Trazado denso entre la 1ª y la última parada.
  for (var i = 0; i <= 40; i++) {
    shape.add(LatLng(lat0, -16.30 + i * 0.0002));
  }

  test('avisa cuando faltan 2 paradas para el destino (parada índice 4)', () {
    final alarm = GetOffAlarm(
      stops: stops,
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.stopsBefore(2),
    );

    var t = DateTime(2026, 1, 1, 12, 0, 0);
    LatLng at(double lon) => LatLng(lat0, lon);

    // En la parada 0: faltan 4, no suena.
    var s = alarm.update(at(-16.300), t);
    expect(s.shouldRing, isFalse);
    expect(s.stopsRemaining, 4);

    // Avanza a la parada 2 (faltan 2): debe sonar.
    t = t.add(const Duration(seconds: 60));
    s = alarm.update(at(-16.2960), t);
    expect(s.stopsRemaining, lessThanOrEqualTo(2));
    expect(s.shouldRing, isTrue);

    // No vuelve a sonar en la siguiente actualización.
    t = t.add(const Duration(seconds: 30));
    s = alarm.update(at(-16.2950), t);
    expect(s.shouldRing, isFalse);
  });

  test('detecta llegada al destino', () {
    final alarm = GetOffAlarm(
      stops: stops,
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.metersBefore(50),
    );
    final t = DateTime(2026, 1, 1, 12, 0, 0);
    final s = alarm.update(LatLng(lat0, -16.2920), t); // sobre la última parada
    expect(s.arrived, isTrue);
  });
}
