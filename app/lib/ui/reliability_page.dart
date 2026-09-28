import 'package:flutter/material.dart';

import '../alarm/reliability.dart';

/// Pantalla "Fiabilidad de la alarma": comprueba permisos y ajustes de los que
/// depende que la alarma suene en segundo plano, con acciones para arreglarlos
/// y la guía específica del fabricante (anti "OEM killers").
class ReliabilityPage extends StatefulWidget {
  const ReliabilityPage({super.key});

  @override
  State<ReliabilityPage> createState() => _ReliabilityPageState();
}

class _ReliabilityPageState extends State<ReliabilityPage> {
  ReliabilityStatus? _s;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await Reliability.check();
    if (mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiabilidad de la alarma'),
        actions: [
          IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Volver a comprobar'),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (s.essentialsOk)
                  const _Banner(
                    color: Color(0xFFE8F5E9),
                    icon: Icons.check_circle,
                    text: 'Todo listo: la alarma debería sonar con la pantalla '
                        'apagada.',
                  )
                else
                  const _Banner(
                    color: Color(0xFFFFF3E0),
                    icon: Icons.warning_amber,
                    text: 'Faltan permisos o ajustes para que la alarma sea '
                        'fiable en segundo plano.',
                  ),
                _CheckTile(
                  ok: s.notifications,
                  title: 'Notificaciones',
                  subtitle: 'Necesarias para avisarte.',
                  actionLabel: 'Permitir',
                  onAction: () async {
                    await Reliability.requestNotifications();
                    _refresh();
                  },
                ),
                _CheckTile(
                  ok: s.locationAlways,
                  title: 'Ubicación "siempre"',
                  subtitle: s.locationWhileInUse && !s.locationAlways
                      ? 'Tienes "mientras se usa"; para la pantalla apagada hace '
                          'falta "Permitir siempre".'
                      : 'Necesaria para seguir el trayecto en segundo plano.',
                  actionLabel: 'Ajustar',
                  onAction: () async {
                    await Reliability.requestLocation();
                    _refresh();
                  },
                ),
                _CheckTile(
                  ok: s.batteryUnrestricted,
                  title: 'Sin restricción de batería',
                  subtitle: 'Evita que el sistema congele la alarma.',
                  actionLabel: 'Permitir',
                  onAction: () async {
                    await Reliability.requestBatteryExemption();
                    _refresh();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.phone_android),
                  title: Text('Tu móvil: ${s.manufacturer}'),
                  subtitle: const Text(
                      'Algunos fabricantes cierran las apps en segundo plano.'),
                ),
                if (s.oemTip != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(s.oemTip!),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: Reliability.openBatterySettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Abrir ajustes de batería'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        color: color,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.black87))),
        ]),
      );
}

class _CheckTile extends StatelessWidget {
  final bool ok;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  const _CheckTile({
    required this.ok,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.red),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: ok ? null : TextButton(onPressed: onAction, child: Text(actionLabel)),
      );
}
