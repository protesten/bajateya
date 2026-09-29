import 'package:flutter/material.dart';

import 'reliability_page.dart';

/// Ayuda dentro de la app: qué es, cómo se usa y solución de problemas.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda · Cómo funciona')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _intro(context),

          _section(
            context,
            icon: Icons.info_outline,
            title: '¿Qué es Bájate Aquí?',
            children: const [
              _P('Una app para moverte en guagua por Tenerife con una función que las '
                  'demás no tienen: la alarma de bajada. Le dices dónde te bajas y te '
                  'avisa (vibración + sonido) al acercarte, para que puedas ir '
                  'tranquilo aunque no conozcas la zona.'),
              _P('Además: llegadas en tiempo real, horarios (incluso sin conexión), '
                  'la última guagua del día, favoritas y avisar a un familiar.'),
            ],
          ),

          _section(
            context,
            icon: Icons.health_and_safety,
            title: 'Antes de empezar: que la alarma no falle',
            initiallyExpanded: true,
            children: [
              const _P('Para que suene con la pantalla apagada, deja en verde estas '
                  'tres cosas y sigue el consejo de tu fabricante:'),
              const _Bullet('Notificaciones activadas.'),
              const _Bullet('Ubicación «Permitir siempre» + ubicación precisa.'),
              const _Bullet('Sin restricción de batería.'),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ReliabilityPage(),
                  )),
                  icon: const Icon(Icons.tune),
                  label: const Text('Abrir «Fiabilidad de la alarma»'),
                ),
              ),
            ],
          ),

          _section(
            context,
            icon: Icons.search,
            title: 'Buscar una parada',
            children: const [
              _P('Escribe el nombre de la parada o su código (el número de la '
                  'marquesina) en el buscador de la pantalla principal, o usa el '
                  'botón Mapa. Con el buscador vacío verás tus paradas favoritas.'),
            ],
          ),

          _section(
            context,
            icon: Icons.schedule,
            title: 'Llegadas, horario y última guagua',
            children: const [
              _P('Dentro de una parada tienes dos pestañas:'),
              _Bullet('Tiempo real: los minutos que faltan de verdad (con conexión).'),
              _Bullet('Horario: las salidas previstas del horario oficial. Funciona '
                  'sin conexión.'),
              _P('En la pestaña Horario está el botón «¿Cuál es la última guagua de '
                  'hoy?». Marca la parada con la estrella ⭐ para tenerla en favoritas.'),
            ],
          ),

          _section(
            context,
            icon: Icons.notifications_active,
            title: 'Poner la alarma de bajada',
            initiallyExpanded: true,
            children: const [
              _Step(1, 'Abre tu parada y toca la línea que vas a coger (o pulsa el '
                  'botón Alarma). También desde el Mapa.'),
              _Step(2, 'Elige hacia dónde vas (el sentido).'),
              _Step(3, 'Elige tu parada de destino.'),
              _Step(4, 'Elige cuándo avisar: 2 paradas antes, o por minutos o metros.'),
              _Step(5, 'Pulsa «Iniciar alarma», sube a la guagua y bloquea el móvil. '
                  'Cuando te acerques, vibrará y sonará.'),
              _P('Para quitarla: usa el aviso «Alarma activa → Detener» del inicio, o '
                  'el botón Detener de la notificación.'),
            ],
          ),

          _section(
            context,
            icon: Icons.share,
            title: 'Avisar a alguien',
            children: const [
              _P('Durante el viaje, el botón «Avisar a alguien» abre WhatsApp o SMS '
                  'con un mensaje listo («Voy en la línea X hacia Y, te aviso al '
                  'llegar»). Útil para avisar a familiares. Al llegar, cambia a '
                  '«Avisar de que he llegado».'),
            ],
          ),

          _section(
            context,
            icon: Icons.help_outline,
            title: 'Si algo va mal',
            children: const [
              _Bullet('No suena con la pantalla apagada → repasa «Fiabilidad de la '
                  'alarma»; casi siempre es el ahorro de batería del fabricante.'),
              _Bullet('Pone «posición incierta» → puede que vayas en el sentido '
                  'equivocado o que haya poca señal GPS; en un trayecto normal '
                  'desaparece al subirte.'),
              _Bullet('No aparecen llegadas → el tiempo real puede no tener datos para '
                  'esa parada a esa hora; mira la pestaña Horario.'),
            ],
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'App no oficial. Datos: TITSA / Cabildo de Tenerife (datos.tenerife.es).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) => Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.secondaryContainer,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bájate Aquí',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Que la guagua te avise cuándo bajarte.'),
          ],
        ),
      );

  Widget _section(BuildContext context,
      {required IconData icon,
      required String title,
      required List<Widget> children,
      bool initiallyExpanded = false}) {
    return ExpansionTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      initiallyExpanded: initiallyExpanded,
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(height: 1.45)),
      );
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
          ],
        ),
      );
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step(this.n, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text('$n',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
          ],
        ),
      );
}
