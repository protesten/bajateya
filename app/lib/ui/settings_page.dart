import 'package:flutter/material.dart';

import '../data/data_updater.dart';
import 'data_update_ui.dart';

/// Ajustes: información de los datos, preferencia solo-WiFi y comprobación manual.
class SettingsPage extends StatefulWidget {
  final DataUpdater updater;
  const SettingsPage({super.key, required this.updater});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DataManifest? _installed;
  bool _wifiOnly = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final installed = await widget.updater.installedManifest();
    final wifiOnly = await widget.updater.wifiOnly();
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _wifiOnly = wifiOnly;
    });
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final check = await widget.updater.checkForUpdate(force: true);
    if (!mounted) return;
    setState(() => _checking = false);

    if (check.offline) {
      _snack('Sin conexión. Inténtalo más tarde.');
      return;
    }
    if (check.incompatible) {
      _snack('Hay datos nuevos, pero requieren actualizar la app.');
      return;
    }
    if (!check.available) {
      _snack('Ya tienes los datos más recientes.');
      return;
    }
    // Hay actualización: preguntar (muestra tamaño y avisa si es red móvil).
    final ok = await showUpdatePrompt(context, widget.updater, check);
    if (ok) _load();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final m = _installed;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _SectionTitle('Datos de transporte'),
          ListTile(
            leading: const Icon(Icons.dataset),
            title: const Text('Versión de los datos'),
            subtitle: Text(m == null
                ? 'Cargando…'
                : 'Versión ${m.version}'
                    '${m.validTo != null ? " · válidos hasta ${_fmt(m.validTo!)}" : ""}'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Actualizar solo por WiFi'),
            subtitle: const Text(
                'Si está activo, con datos móviles se te preguntará antes de descargar.'),
            value: _wifiOnly,
            onChanged: (v) async {
              await widget.updater.setWifiOnly(v);
              setState(() => _wifiOnly = v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Comprobar actualizaciones ahora'),
            trailing: _checking
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _checking ? null : _checkNow,
          ),
          const Divider(),
          const _SectionTitle('Acerca de'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Bájate Aquí'),
            subtitle: Text(
                'App no oficial. Datos: TITSA / Cabildo de Tenerife.'),
          ),
        ],
      ),
    );
  }

  static String _fmt(String d) => d.length == 8
      ? '${d.substring(6, 8)}/${d.substring(4, 6)}/${d.substring(0, 4)}'
      : d;
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
