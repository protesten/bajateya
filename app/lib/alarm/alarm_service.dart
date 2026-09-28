import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';

import 'get_off_alarm.dart';
import 'trip_plan.dart';

const String _kPlanKey = 'trip_plan_json';
const int _kRingNotificationId = 7001;

/// Punto de entrada del isolate del servicio en primer plano.
@pragma('vm:entry-point')
void alarmServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_TripTaskHandler());
}

/// API pública para iniciar/parar el seguimiento de la alarma de bajada.
class AlarmService {
  /// Inicializa canales de notificación y opciones del servicio. Llamar 1 vez.
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bajate_aqui_tracking',
        channelName: 'Seguimiento del viaje',
        channelDescription: 'Muestra las paradas que faltan para tu destino.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(), // el GPS marca el ritmo
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Pide permisos necesarios (notificaciones, ubicación, batería).
  static Future<bool> ensurePermissions() async {
    // Notificaciones
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    if (notif != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    // Ubicación
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;

    // Ignorar optimización de batería (mejora la fiabilidad en 2º plano).
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }

  /// Arranca el seguimiento de un viaje concreto.
  static Future<void> start(TripPlan plan) async {
    await FlutterForegroundTask.saveData(key: _kPlanKey, value: plan.encode());
    await FlutterForegroundTask.startService(
      serviceId: 700,
      notificationTitle: 'Siguiendo tu viaje',
      notificationText: 'Preparando el seguimiento…',
      notificationIcon: null,
      callback: alarmServiceCallback,
    );
  }

  static Future<void> stop() => FlutterForegroundTask.stopService();

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  /// Suscribe a los datos que envía el servicio (estado y evento de aviso).
  static void addListener(void Function(Object data) cb) =>
      FlutterForegroundTask.addTaskDataCallback(cb);

  static void removeListener(void Function(Object data) cb) =>
      FlutterForegroundTask.removeTaskDataCallback(cb);
}

/// Handler que corre en el isolate del servicio: sigue el GPS y decide el aviso.
class _TripTaskHandler extends TaskHandler {
  GetOffAlarm? _alarm;
  TripPlan? _plan;
  StreamSubscription<Position>? _gps;
  Timer? _staleTimer;
  DateTime? _lastFixAt;
  String _band = 'mid';
  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _rang = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notif.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));

    final json = await FlutterForegroundTask.getData<String>(key: _kPlanKey);
    if (json == null) return;
    final plan = TripPlan.decode(json);
    _plan = plan;
    _alarm = plan.buildAlarm();

    _startGps('mid');
    // Dead reckoning: si el GPS se congela (túnel/sombra), estimar el avance.
    _staleTimer = Timer.periodic(const Duration(seconds: 8), (_) => _onStale());
  }

  /// Precisión y filtro de distancia según lo cerca que estemos del destino,
  /// para ahorrar batería lejos y afinar en la recta final.
  LocationSettings _settingsForBand(String band) {
    switch (band) {
      case 'near': // < 1,5 km
        return const LocationSettings(
            accuracy: LocationAccuracy.best, distanceFilter: 5);
      case 'far': // > 3 km
        return const LocationSettings(
            accuracy: LocationAccuracy.medium, distanceFilter: 50);
      default: // mid
        return const LocationSettings(
            accuracy: LocationAccuracy.high, distanceFilter: 20);
    }
  }

  String _bandFor(double metersRemaining) => metersRemaining < 1500
      ? 'near'
      : (metersRemaining > 3000 ? 'far' : 'mid');

  void _startGps(String band) {
    _band = band;
    _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: _settingsForBand(band),
    ).listen(_onPosition);
  }

  void _onStale() {
    final alarm = _alarm;
    final plan = _plan;
    if (alarm == null || plan == null || _rang) return;
    if (_lastFixAt == null ||
        DateTime.now().difference(_lastFixAt!) < const Duration(seconds: 12)) {
      return; // el GPS sigue llegando; nada que estimar
    }
    final st = alarm.predictWithoutFix(DateTime.now());
    FlutterForegroundTask.updateService(
      notificationTitle: 'Línea ${plan.lineName} → ${plan.destination.name}',
      notificationText: 'Señal GPS débil… siguiendo por estimación',
    );
    if (st != null && st.shouldRing && !_rang) {
      _rang = true;
      _ring(plan);
    }
  }

  void _onPosition(Position pos) {
    final alarm = _alarm;
    final plan = _plan;
    if (alarm == null || plan == null) return;
    _lastFixAt = DateTime.now();

    final st = alarm.update(
      LatLng(pos.latitude, pos.longitude),
      DateTime.now(),
      accuracy: pos.accuracy,
    );

    // Ajusta la cadencia del GPS a la distancia restante (ahorro de batería).
    final band = _bandFor(st.metersRemaining);
    if (band != _band) _startGps(band);

    // Actualiza la notificación persistente del viaje.
    final eta =
        st.etaSeconds == null ? '' : ' · ~${(st.etaSeconds! / 60).ceil()} min';
    final body = st.offRoute
        ? 'Posición incierta (¿sentido correcto?)'
        : st.arrived
            ? 'Estás llegando a tu parada'
            : 'Faltan ${st.stopsRemaining} paradas'
                ' (${st.metersRemaining.round()} m)$eta';
    FlutterForegroundTask.updateService(
      notificationTitle: 'Línea ${plan.lineName} → ${plan.destination.name}',
      notificationText: body,
    );

    // Envía el estado a la UI (si la app está abierta).
    FlutterForegroundTask.sendDataToMain({
      'type': 'status',
      'stopsRemaining': st.stopsRemaining,
      'metersRemaining': st.metersRemaining,
      'etaSeconds': st.etaSeconds,
      'arrived': st.arrived,
      'offRoute': st.offRoute,
      'lat': pos.latitude,
      'lon': pos.longitude,
    });

    if (st.shouldRing && !_rang) {
      _rang = true;
      _ring(plan);
    }
    if (st.arrived) {
      _gps?.cancel();
      _staleTimer?.cancel();
    }
  }

  Future<void> _ring(TripPlan plan) async {
    // Vibración marcada.
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: const [0, 600, 300, 600, 300, 900]);
    }
    // Notificación de aviso, con sonido y prioridad alta.
    await _notif.show(
      _kRingNotificationId,
      '¡Prepárate para bajar!',
      'Tu parada (${plan.destination.name}) está muy cerca.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'bajate_aqui_alarm',
          'Alarma de bajada',
          channelDescription: 'Aviso cuando te acercas a tu parada de destino.',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
    FlutterForegroundTask.sendDataToMain({'type': 'ring'});
  }

  // El GPS marca el ritmo; no usamos eventos periódicos.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _staleTimer?.cancel();
    await _gps?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'stop') {
      _staleTimer?.cancel();
      _gps?.cancel();
    }
  }
}
