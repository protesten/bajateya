import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

/// Estado de las condiciones de las que depende que la alarma suene de verdad.
class ReliabilityStatus {
  final bool notifications; // permiso de notificaciones
  final bool locationWhileInUse; // ubicación al menos "mientras se usa"
  final bool locationAlways; // ubicación "siempre" (necesaria en 2º plano)
  final bool batteryUnrestricted; // exención de optimización de batería
  final String manufacturer;
  final String? oemTip; // consejo de autoarranque específico del fabricante

  const ReliabilityStatus({
    required this.notifications,
    required this.locationWhileInUse,
    required this.locationAlways,
    required this.batteryUnrestricted,
    required this.manufacturer,
    required this.oemTip,
  });

  /// ¿Están cubiertos los mínimos para que la alarma sea fiable?
  bool get essentialsOk =>
      notifications && locationAlways && batteryUnrestricted;
}

/// Comprobaciones y acciones para maximizar la fiabilidad de la alarma en
/// segundo plano, incluida la guía frente a los "asesinos de tareas" de algunos
/// fabricantes (Xiaomi, Huawei, Samsung, Oppo…).
class Reliability {
  static Future<ReliabilityStatus> check() async {
    final notif = await FlutterForegroundTask.checkNotificationPermission();
    final perm = await Geolocator.checkPermission();
    final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;

    String manufacturer = 'genérico';
    if (Platform.isAndroid) {
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        manufacturer = info.manufacturer;
      } catch (_) {}
    }

    return ReliabilityStatus(
      notifications: notif == NotificationPermission.granted,
      locationWhileInUse: perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always,
      locationAlways: perm == LocationPermission.always,
      batteryUnrestricted: battery,
      manufacturer: manufacturer,
      oemTip: _oemTip(manufacturer),
    );
  }

  static Future<void> requestNotifications() =>
      FlutterForegroundTask.requestNotificationPermission();

  static Future<void> requestLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // El permiso "siempre" (segundo plano) suele exigir ir a ajustes.
    if (perm != LocationPermission.always) {
      await Geolocator.openAppSettings();
    }
  }

  static Future<void> requestBatteryExemption() async {
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<void> openBatterySettings() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();

  /// Consejo de autoarranque/segundo plano según el fabricante. No hay una API
  /// estándar para abrir esas pantallas, así que guiamos con texto claro.
  static String? _oemTip(String manufacturer) {
    final m = manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
      return 'Xiaomi/Redmi/POCO (MIUI/HyperOS): Ajustes → Aplicaciones → Bájate '
          'Aquí → activa "Inicio automático" y en "Ahorro de batería" elige '
          '"Sin restricciones". Bloquea la app en Recientes (icono del candado).';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return 'Huawei/Honor: Ajustes → Batería → Inicio de aplicaciones → busca '
          'Bájate Aquí, desactiva "Gestionar automáticamente" y activa '
          '"Inicio automático", "Inicio secundario" y "Ejecutar en segundo plano".';
    }
    if (m.contains('samsung')) {
      return 'Samsung: Ajustes → Batería → Límites de uso en segundo plano → '
          'quita la app de "Apps en reposo/inactivas". En la ficha de la app, '
          'Batería → "Sin restricciones".';
    }
    if (m.contains('oppo') ||
        m.contains('realme') ||
        m.contains('oneplus') ||
        m.contains('oplus')) {
      return 'Oppo/Realme/OnePlus (ColorOS/OxygenOS): Ajustes → Batería → '
          'permite "Actividad en segundo plano" e "Inicio automático" para '
          'Bájate Aquí.';
    }
    if (m.contains('vivo')) {
      return 'vivo (Funtouch/OriginOS): Ajustes → Batería → Consumo en segundo '
          'plano de alta potencia / Inicio automático → permite Bájate Aquí.';
    }
    return 'Si la alarma no suena con la pantalla apagada, busca en los ajustes '
        'de tu móvil "Inicio automático" o "Actividad en segundo plano" y '
        'permítelos para Bájate Aquí.';
  }
}
