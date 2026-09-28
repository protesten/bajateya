import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart'
    show getApplicationSupportDirectory;
import 'package:shared_preferences/shared_preferences.dart';

/// Metadatos de una versión de la base de datos GTFS.
class DataManifest {
  final String version;
  final String? validFrom; // AAAAMMDD
  final String? validTo; // AAAAMMDD
  final String sqliteUrl;
  final String sqliteSha256;
  final int sqliteSize;
  final String minAppVersion;

  DataManifest({
    required this.version,
    required this.validFrom,
    required this.validTo,
    required this.sqliteUrl,
    required this.sqliteSha256,
    required this.sqliteSize,
    required this.minAppVersion,
  });

  factory DataManifest.fromJson(Map<String, dynamic> j) => DataManifest(
        version: j['version'] as String,
        validFrom: j['valid_from'] as String?,
        validTo: j['valid_to'] as String?,
        sqliteUrl: j['sqlite_url'] as String? ?? '',
        sqliteSha256: j['sqlite_sha256'] as String? ?? '',
        sqliteSize: (j['sqlite_size'] as num?)?.toInt() ?? 0,
        minAppVersion: j['min_app_version'] as String? ?? '0.0.0',
      );

  String encode() => jsonEncode({
        'version': version,
        'valid_from': validFrom,
        'valid_to': validTo,
        'sqlite_url': sqliteUrl,
        'sqlite_sha256': sqliteSha256,
        'sqlite_size': sqliteSize,
        'min_app_version': minAppVersion,
      });
}

enum UpdateResult { upToDate, updated, skippedThrottled, offline, incompatible, failed }

/// Resultado de comprobar (sin descargar la BD todavía).
class UpdateCheck {
  final bool available; // hay una versión nueva y compatible
  final DataManifest? remote; // manifest remoto (si se pudo leer)
  final bool offline;
  final bool incompatible; // requiere una versión más nueva de la app
  final bool onWifi; // conexión no medida (WiFi/ethernet)

  const UpdateCheck({
    required this.available,
    required this.remote,
    required this.offline,
    required this.incompatible,
    required this.onWifi,
  });

  /// Tamaño de la descarga en MB (para mostrar al usuario).
  double get sizeMb => (remote?.sqliteSize ?? 0) / (1024 * 1024);
}

/// Gestiona la versión local de la base de datos GTFS y su actualización.
///
/// Flujo:
///  - [ensureInstalled] copia la BD empaquetada la primera vez.
///  - [checkForUpdate] pide el manifest remoto, compara versión/hash y, si hay
///    algo nuevo compatible, descarga el .sqlite, lo verifica (SHA-256 + tamaño)
///    y lo intercambia de forma atómica. La nueva BD se usa en el próximo abrir.
class DataUpdater {
  final String manifestUrl;
  final String appVersion;
  final Duration minInterval;

  DataUpdater({
    required this.manifestUrl,
    required this.appVersion,
    this.minInterval = const Duration(hours: 20),
  });

  static const _kLastCheck = 'gtfs_last_check_epoch';
  static const _kWifiOnly = 'gtfs_wifi_only';

  /// Preferencia: descargar actualizaciones solo por WiFi (por defecto, sí).
  Future<bool> wifiOnly() async =>
      (await SharedPreferences.getInstance()).getBool(_kWifiOnly) ?? true;

  Future<void> setWifiOnly(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_kWifiOnly, value);

  /// ¿La conexión actual es no medida (WiFi/ethernet)?
  Future<bool> onUnmeteredNetwork() async {
    final types = await Connectivity().checkConnectivity();
    return types.contains(ConnectivityResult.wifi) ||
        types.contains(ConnectivityResult.ethernet);
  }

  Future<bool> isOffline() async {
    final types = await Connectivity().checkConnectivity();
    return types.isEmpty || types.every((t) => t == ConnectivityResult.none);
  }

  Future<String> get _dir async =>
      (await getApplicationSupportDirectory()).path;
  Future<String> get dbPath async => p.join(await _dir, 'guaguas.sqlite');
  Future<String> get _installedManifestPath async =>
      p.join(await _dir, 'installed_manifest.json');

  /// Copia la BD y el manifest empaquetados si aún no hay datos instalados.
  Future<void> ensureInstalled() async {
    final db = File(await dbPath);
    if (await db.exists()) return;
    final bytes = await rootBundle.load('assets/guaguas.sqlite');
    await db.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final man = await rootBundle.loadString('assets/manifest.json');
    await File(await _installedManifestPath).writeAsString(man);
  }

  Future<DataManifest?> installedManifest() async {
    final f = File(await _installedManifestPath);
    if (!await f.exists()) return null;
    return DataManifest.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  /// ¿Está el calendario a punto de caducar? (para forzar comprobación).
  Future<bool> isExpiringSoon({int days = 14}) async {
    final m = await installedManifest();
    if (m?.validTo == null) return false;
    final vt = DateTime.tryParse(
        '${m!.validTo!.substring(0, 4)}-${m.validTo!.substring(4, 6)}-${m.validTo!.substring(6, 8)}');
    if (vt == null) return false;
    return vt.difference(DateTime.now()).inDays <= days;
  }

  /// Comprueba si hay una versión nueva **sin descargar la BD** (solo el
  /// manifest, que son bytes). No aplica nada: la decisión de descargar la toma
  /// quien llama, según la red y la preferencia del usuario.
  ///
  /// [force] ignora el intervalo mínimo (para el botón "Comprobar ahora").
  Future<UpdateCheck> checkForUpdate({bool force = false}) async {
    await ensureInstalled();
    final onWifi = await onUnmeteredNetwork();

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_kLastCheck) ?? 0;
    if (!force &&
        DateTime.now().difference(DateTimeX.fromMs(last)) < minInterval) {
      return UpdateCheck(
          available: false, remote: null, offline: false,
          incompatible: false, onWifi: onWifi);
    }

    DataManifest remote;
    try {
      final res = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        return UpdateCheck(
            available: false, remote: null, offline: false,
            incompatible: false, onWifi: onWifi);
      }
      remote = DataManifest.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return UpdateCheck(
          available: false, remote: null, offline: true,
          incompatible: false, onWifi: onWifi);
    }

    await prefs.setInt(_kLastCheck, now); // comprobado aunque no haya cambios

    final installed = await installedManifest();
    // La VERSIÓN identifica el conjunto de datos; el SHA-256 solo sirve para
    // verificar la descarga. Dos construcciones de la misma versión pueden dar
    // bytes distintos (SQLite no es determinista), así que no comparamos hash
    // aquí para no forzar re-descargas innecesarias.
    final same = installed != null && installed.version == remote.version;
    if (same) {
      return UpdateCheck(
          available: false, remote: remote, offline: false,
          incompatible: false, onWifi: onWifi);
    }

    final incompatible = _versionLt(appVersion, remote.minAppVersion);
    return UpdateCheck(
        available: !incompatible, remote: remote, offline: false,
        incompatible: incompatible, onWifi: onWifi);
  }

  /// Descarga la BD del manifest [remote], la verifica (tamaño + SHA-256) y la
  /// intercambia de forma atómica. Se aplica al reiniciar. Devuelve el resultado.
  Future<UpdateResult> downloadAndApply(DataManifest remote) async {
    try {
      final tmp = File('${await dbPath}.new');
      final res = await http
          .get(Uri.parse(remote.sqliteUrl))
          .timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) return UpdateResult.failed;

      final bytes = res.bodyBytes;
      if (bytes.length != remote.sqliteSize) return UpdateResult.failed;
      if (sha256.convert(bytes).toString() != remote.sqliteSha256) {
        return UpdateResult.failed;
      }
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(await dbPath); // intercambio atómico
      await File(await _installedManifestPath).writeAsString(remote.encode());
      return UpdateResult.updated;
    } catch (_) {
      return UpdateResult.failed;
    }
  }

  /// Compara versiones semánticas simples "a.b.c". true si [a] < [b].
  static bool _versionLt(String a, String b) {
    List<int> parts(String v) =>
        v.split(RegExp(r'[.+-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }
}

extension DateTimeX on DateTime {
  static DateTime fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);
}
