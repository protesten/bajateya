import 'package:flutter_test/flutter_test.dart';
import 'package:bajate_aqui/alarm/get_off_alarm.dart';

void main() {
  // Trayecto recto de 5 paradas separadas ~200 m sobre una línea E-O.
  const lat0 = 28.45;
  List<TripStop> makeStops() {
    final stops = <TripStop>[];
    for (var i = 0; i < 5; i++) {
      final lon = -16.30 + i * 0.002; // ~200 m por paso a esta latitud
      stops.add(TripStop(
        stopId: 1000 + i,
        name: 'Parada $i',
        pos: LatLng(lat0, lon),
        distFromStart: i * 200.0,
      ));
    }
    return stops;
  }

  // Trazado denso entre la 1ª y la última parada.
  final shape = <LatLng>[
    for (var i = 0; i <= 40; i++) LatLng(lat0, -16.30 + i * 0.0002),
  ];

  LatLng at(double lon) => LatLng(lat0, lon);

  test('avisa cuando faltan 2 paradas para el destino (parada índice 4)', () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.stopsBefore(2),
    );

    var t = DateTime(2026, 1, 1, 12, 0, 0);
    var s = alarm.update(at(-16.300), t);
    expect(s.shouldRing, isFalse);
    expect(s.stopsRemaining, 4);

    t = t.add(const Duration(seconds: 60));
    s = alarm.update(at(-16.2960), t);
    expect(s.stopsRemaining, lessThanOrEqualTo(2));
    expect(s.shouldRing, isTrue);

    t = t.add(const Duration(seconds: 30));
    s = alarm.update(at(-16.2950), t);
    expect(s.shouldRing, isFalse); // no repite
  });

  test('detecta llegada al destino', () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.metersBefore(50),
    );
    final s = alarm.update(at(-16.2920), DateTime(2026, 1, 1, 12));
    expect(s.arrived, isTrue);
  });

  test('marca fuera de ruta cuando la posición se aleja del trazado', () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.stopsBefore(1),
    );
    // ~0.01º de latitud (~1,1 km) fuera de la línea E-O.
    final s = alarm.update(LatLng(lat0 + 0.01, -16.296), DateTime(2026, 1, 1, 12));
    expect(s.offRoute, isTrue);
    expect(s.shouldRing, isFalse); // no se fía estando fuera de ruta
  });

  test('red de seguridad: avisa por cercanía directa aunque no haya trigger normal',
      () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.minutesBefore(1), // difícil de cumplir sin ETA
      safetyRadius: 120,
    );
    // Muy cerca del destino en línea recta.
    final s = alarm.update(at(-16.2921), DateTime(2026, 1, 1, 12));
    expect(s.shouldRing, isTrue);
  });

  test('subir a mitad de trayecto se localiza en el primer fix', () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.stopsBefore(1),
    );
    // Primer fix ya en la parada 3 (~600 m): debe contar bien las restantes.
    final s = alarm.update(at(-16.2940), DateTime(2026, 1, 1, 12));
    expect(s.offRoute, isFalse);
    expect(s.stopsRemaining, lessThanOrEqualTo(2));
  });

  test('dead reckoning avisa en túnel si la estimación alcanza el disparo', () {
    final alarm = GetOffAlarm(
      stops: makeStops(),
      destIndex: 4,
      shape: shape,
      config: const AlarmConfig.metersBefore(60),
    );
    var t = DateTime(2026, 1, 1, 12, 0, 0);
    // Dos fixes para estimar velocidad (~6,5 m/s).
    alarm.update(at(-16.2980), t);
    t = t.add(const Duration(seconds: 30));
    alarm.update(at(-16.2960), t); // avanza ~200 m en 30 s (~6,5 m/s)
    // Se pierde el GPS; 55 s después la posición estimada ya estaría a <60 m.
    t = t.add(const Duration(seconds: 55));
    final s = alarm.predictWithoutFix(t);
    expect(s, isNotNull);
    expect(s!.shouldRing, isTrue);
  });
}
