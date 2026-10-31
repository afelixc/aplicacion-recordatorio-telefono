import 'package:flutter/material.dart';

/// Ejemplos de cómo pedir cada tipo de recordatorio. Son solo para leer:
/// tocarlos no crea nada.
const exampleGroups = <(IconData, String, List<String>)>[
  (
    Icons.event,
    'Una sola vez',
    [
      'Mañana a las 20 llamar a Juan',
      'Recordame el viernes a las 9 de la mañana lavar el auto',
      'El 15 de diciembre a las 10 pagar el seguro',
      'En 2 horas sacar la ropa del lavarropas',
    ],
  ),
  (
    Icons.today,
    'Todos los días',
    [
      'Todos los días a las 8 tomar la pastilla',
      'Cada noche a las 22 cerrar la garrafa',
    ],
  ),
  (
    Icons.view_week,
    'Algunos días de la semana',
    [
      'Todos los lunes y jueves a las 19 ir al gimnasio',
      'De lunes a viernes a las 7 sacar la basura',
    ],
  ),
  (
    Icons.calendar_month,
    'Todos los meses',
    [
      'Todos los meses el día 10 a las 9 pagar el alquiler',
      'El 1 de cada mes a las 12 pagar la tarjeta',
    ],
  ),
  (
    Icons.cake,
    'Todos los años',
    [
      'Todos los años el 3 de mayo cumpleaños de mamá',
      'Cada 20 de enero a las 9 renovar el seguro del auto',
    ],
  ),
  (
    Icons.event_note,
    'Días puntuales',
    ['El 5, el 12 y el 19 de noviembre a las 18 clase de guitarra'],
  ),
  (
    Icons.playlist_add,
    'Dos de una vez (máximo dos)',
    ['En 1 minuto lente y en 3 minutos pelota'],
  ),
];

const exampleTips = [
  'Decí qué, el día y la hora. Si falta algo, te lo pregunto.',
  'Si no decís la hora, te pregunto a qué hora querés el aviso.',
  'Podés hablar normal, como le hablarías a una persona.',
  'Después de guardarlo podés tocar "Modificar" para corregir lo que quieras.',
];

Future<void> showExamples(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    maxChildSize: 0.95,
    builder: (context, scroll) => _ExamplesView(scroll: scroll),
  ),
);

class _ExamplesView extends StatelessWidget {
  const _ExamplesView({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('Ejemplos y formas de pedirlo', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Son solo para que veas cómo decirlo. Para crear uno, cerrá esto y '
          'hablá o escribí con tus palabras.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        for (final (icon, title, examples) in exampleGroups) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in examples)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('“$e”', style: theme.textTheme.bodyMedium),
            ),
        ],
        const SizedBox(height: 16),
        Text('Consejos', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final t in exampleTips)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(t)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
