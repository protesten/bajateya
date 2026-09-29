import 'package:flutter/material.dart';

import '../data/gtfs_db.dart';
import 'line_chooser.dart';
import 'trip_setup_page.dart';

/// Muestra las líneas (patrones) que pasan por [stopId] y, al elegir una, abre
/// la configuración de la alarma de bajada. Reutilizable desde lista y mapa.
/// Si [onlyLine] se indica, filtra a esa línea (p. ej. al tocar una llegada).
Future<void> chooseLineForAlarm(
    BuildContext context, GtfsDb db, int stopId, {int? onlyLine}) async {
  var patterns = await db.patternsThroughStop(stopId);
  if (onlyLine != null) {
    patterns = patterns
        .where((p) => int.tryParse('${p['short_name']}') == onlyLine)
        .toList();
  }
  if (!context.mounted) return;
  // Si tras filtrar por línea solo queda un destino, salta directo a configurar.
  if (onlyLine != null && patterns.length == 1) {
    final p = patterns.first;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TripSetupPage(
        db: db,
        patternId: p['pattern_id'] as int,
        shapeId: p['shape_id'] as String?,
        lineName: '${p['short_name']}',
        headsign: '${p['headsign']}',
        boardingStopId: stopId,
      ),
    ));
    return;
  }
  if (patterns.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No hay líneas registradas para esta parada.'),
    ));
    return;
  }

  final chosen = await showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => LineChooserSheet(
      patterns: patterns,
      title: onlyLine != null ? '¿Hacia dónde vas?' : '¿Qué línea vas a coger?',
    ),
  );
  if (chosen == null || !context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TripSetupPage(
      db: db,
      patternId: chosen['pattern_id'] as int,
      shapeId: chosen['shape_id'] as String?,
      lineName: '${chosen['short_name']}',
      headsign: '${chosen['headsign']}',
      boardingStopId: stopId,
    ),
  ));
}

/// Capa de teselas OSM con el User-Agent correcto (requisito de uso de OSM).
/// Para producción conviene un proveedor de teselas propio o de pago.
const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String tileUserAgentPackage = 'com.bajateaqui.bajate_aqui';
