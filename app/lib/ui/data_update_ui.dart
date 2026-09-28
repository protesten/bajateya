import 'package:flutter/material.dart';

import '../data/data_updater.dart';

/// Muestra un diálogo pidiendo permiso para descargar la actualización de datos,
/// indicando el tamaño y avisando si se hará con datos móviles. Si el usuario
/// acepta, descarga y aplica mostrando progreso. Devuelve true si se actualizó.
Future<bool> showUpdatePrompt(
  BuildContext context,
  DataUpdater updater,
  UpdateCheck check,
) async {
  final remote = check.remote;
  if (remote == null) return false;

  final size = check.sizeMb.toStringAsFixed(1);
  final onMobile = !check.onWifi;

  final accept = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hay datos nuevos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versión ${remote.version} · $size MB'),
          if (remote.validTo != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Horarios válidos hasta ${_fmtDate(remote.validTo!)}',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          if (onMobile)
            Text(
              'Estás usando datos móviles. ¿Descargar ahora o esperar a una '
              'red WiFi?',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            )
          else
            const Text('¿Quieres descargar la actualización ahora?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(onMobile ? 'Esperar a WiFi' : 'Ahora no'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(onMobile ? 'Descargar ahora' : 'Descargar'),
        ),
      ],
    ),
  );

  if (accept != true || !context.mounted) return false;

  // Descarga con indicador de progreso (modal no cancelable).
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 20),
        Expanded(child: Text('Descargando datos…')),
      ]),
    ),
  );

  final result = await updater.downloadAndApply(remote);
  if (context.mounted) Navigator.pop(context); // cierra el progreso

  if (context.mounted) {
    final ok = result == UpdateResult.updated;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Datos actualizados. Se aplicarán al reiniciar la app.'
          : 'No se pudo completar la descarga. Inténtalo más tarde.'),
    ));
    return ok;
  }
  return result == UpdateResult.updated;
}

String _fmtDate(String yyyymmdd) {
  if (yyyymmdd.length != 8) return yyyymmdd;
  return '${yyyymmdd.substring(6, 8)}/${yyyymmdd.substring(4, 6)}/${yyyymmdd.substring(0, 4)}';
}
