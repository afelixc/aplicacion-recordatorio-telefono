import 'package:flutter/material.dart';

import '../../core/app_scope.dart';

/// Un color para las tarjetas de Listado → Todos: relleno clarito y borde.
class ListColor {
  const ListColor(this.id, this.name, this.fill, this.border);

  final String id;
  final String name;
  final Color fill;
  final Color border;

  /// Relleno según el tema (en modo oscuro, el clarito no deja leer).
  Color fillFor(Brightness b) =>
      b == Brightness.dark ? border.withValues(alpha: 0.28) : fill;
}

const listColors = <ListColor>[
  ListColor('azul', 'Azul', Color(0xFFE3EBFF), Color(0xFF8FA2E0)),
  ListColor('celeste', 'Celeste', Color(0xFFDDF4FA), Color(0xFF7CC7DB)),
  ListColor('verde', 'Verde', Color(0xFFE2F5E4), Color(0xFF86C38E)),
  ListColor('amarillo', 'Amarillo', Color(0xFFFFF4D6), Color(0xFFE8C77A)),
  ListColor('naranja', 'Naranja', Color(0xFFFFE8D6), Color(0xFFF0A868)),
  ListColor('rosa', 'Rosa', Color(0xFFFCE4EC), Color(0xFFE8A0B8)),
  ListColor('violeta', 'Violeta', Color(0xFFEDE4FB), Color(0xFFB49BE0)),
  ListColor('gris', 'Gris', Color(0xFFEEEEEE), Color(0xFFBDBDBD)),
  ListColor('blanco', 'Blanco', Color(0xFFFFFFFF), Color(0xFFD5D8E0)),
];

ListColor listColor(String id) =>
    listColors.firstWhere((c) => c.id == id, orElse: () => listColors.first);

/// Muestra de color redondita.
class ColorDot extends StatelessWidget {
  const ColorDot(
    this.color, {
    super.key,
    this.size = 16,
    this.selected = false,
  });

  final ListColor color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.fillFor(b),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : color.border,
          width: selected ? 3 : 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check, size: size * 0.55, color: color.border)
          : null,
    );
  }
}

/// Renglón arriba de Todos: qué color es cada uno y el botón para cambiarlos.
class ListColorsBar extends StatelessWidget {
  const ListColorsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 2),
        child: Row(
          children: [
            ColorDot(listColor(settings.colorPending)),
            const SizedBox(width: 6),
            Text('Pendientes', style: small),
            const SizedBox(width: 14),
            ColorDot(listColor(settings.colorDone)),
            const SizedBox(width: 6),
            Text('Hechos', style: small),
            const Spacer(),
            TextButton.icon(
              key: const Key('list-colors'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Colores'),
              onPressed: () => showListColors(context),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showListColors(BuildContext context) {
  final settings = AppScope.of(context).settings;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final theme = Theme.of(context);
        Widget row(String title, String selected, bool pending) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in listColors)
                  Tooltip(
                    message: c.name,
                    child: InkWell(
                      key: Key('color-${pending ? 'p' : 'd'}-${c.id}'),
                      customBorder: const CircleBorder(),
                      onTap: () => pending
                          ? settings.setListColor(pending: c.id)
                          : settings.setListColor(done: c.id),
                      child: ColorDot(c, size: 40, selected: c.id == selected),
                    ),
                  ),
              ],
            ),
          ],
        );
        Widget sample(String text, ListColor c, bool done) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.fillFor(theme.brightness),
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: done
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Colores de "Todos"', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Tocá un color. Se guarda solo.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                row('Los que faltan hacer', settings.colorPending, true),
                const SizedBox(height: 20),
                row('Los hechos', settings.colorDone, false),
                const SizedBox(height: 20),
                Text('Así se ven', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                sample(
                  'Llamar al dentista',
                  listColor(settings.colorPending),
                  false,
                ),
                const SizedBox(height: 8),
                sample('Pagar la luz', listColor(settings.colorDone), true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => settings.setListColor(
                        pending: 'azul',
                        done: 'amarillo',
                      ),
                      child: const Text('Volver a los de siempre'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Listo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
