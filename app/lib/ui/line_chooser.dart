import 'package:flutter/material.dart';

/// Hoja inferior con buscador para elegir una línea/destino cuando una parada
/// tiene muchas líneas. Devuelve el patrón elegido (mapa de la BD) o null.
class LineChooserSheet extends StatefulWidget {
  final List<Map<String, Object?>> patterns;
  final String title;
  const LineChooserSheet({super.key, required this.patterns, required this.title});

  @override
  State<LineChooserSheet> createState() => _LineChooserSheetState();
}

class _LineChooserSheetState extends State<LineChooserSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toUpperCase();
    final list = q.isEmpty
        ? widget.patterns
        : widget.patterns.where((p) {
            final n = '${p['short_name']}'.toUpperCase();
            final h = '${p['headsign']}'.toUpperCase();
            return n.contains(q) || h.contains(q);
          }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(widget.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (widget.patterns.length > 6)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: 'Filtrar por número o destino',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final p = list[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${p['short_name']}')),
                  title: Text('${p['headsign']}'),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin resultados.'),
            ),
        ],
      ),
    );
  }
}
