import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/palette.dart';
import '../settings/colors_page.dart';

/// Renglón arriba de Listado → Todos: qué color es cada uno y el botón que
/// lleva a Configuración → Colores.
class ListColorsBar extends StatelessWidget {
  const ListColorsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final night = Theme.of(context).brightness == Brightness.dark;
    final small = Theme.of(context).textTheme.bodySmall;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final c = settings.colorsFor(night: night);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 2),
          child: Row(
            children: [
              SoftDot(softColor(c.pending), night: night),
              const SizedBox(width: 6),
              Text('Pendientes', style: small),
              const SizedBox(width: 14),
              SoftDot(softColor(c.done), night: night),
              const SizedBox(width: 6),
              Text('Hechos', style: small),
              const Spacer(),
              TextButton.icon(
                key: const Key('list-colors'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('Colores'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ColorsPage(startAtNight: night),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Puntito con un relleno suave.
class SoftDot extends StatelessWidget {
  const SoftDot(this.color, {super.key, required this.night, this.size = 16});

  final SoftColor color;
  final bool night;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.fill(night),
      shape: BoxShape.circle,
      border: Border.all(color: color.border(night), width: 1.5),
    ),
  );
}
