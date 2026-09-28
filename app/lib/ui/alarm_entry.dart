import 'package:flutter/material.dart';

import '../data/gtfs_db.dart';
import 'trip_setup_page.dart';

/// Muestra las líneas (patrones) que pasan por [stopId] y, al elegir una, abre
/// la configuración de la alarma de bajada. Reutilizable desde lista y mapa.
Future<void> chooseLineForAlarm(
    BuildContext context, GtfsDb db, int stopId) async {
  final patterns = await db.patternsThroughStop(stopId);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => ListView(
      shrinkWrap: true,
      children: [
        const ListTile(
          title: Text('¿Qué línea vas a coger?',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final p in patterns)
          ListTile(
            leading: CircleAvatar(child: Text('${p['short_name']}')),
            title: Text('${p['headsign']}'),
            onTap: () {
              Navigator.of(context).pop();
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
            },
          ),
        if (patterns.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay líneas registradas para esta parada.'),
          ),
      ],
    ),
  );
}

/// Capa de teselas OSM con el User-Agent correcto (requisito de uso de OSM).
/// Para producción conviene un proveedor de teselas propio o de pago.
const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String tileUserAgentPackage = 'com.bajateaqui.bajate_aqui';
