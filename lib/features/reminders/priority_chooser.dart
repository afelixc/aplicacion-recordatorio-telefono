import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/reminder.dart';
import '../notifications/priority_config.dart';
import '../settings/priorities_page.dart' show priorityColor;

/// Prioridad del recordatorio (Normal · Media · Alta) y "Sonar aunque esté
/// en silencio", debajo de Cancelar / Modificar.
class PriorityChooser extends StatelessWidget {
  const PriorityChooser({
    super.key,
    required this.priority,
    required this.loud,
    this.divider = true,
    required this.onPriority,
    required this.onLoud,
  });

  final ReminderPriority priority;
  final bool loud;

  /// La rayita de arriba (en la tarjeta del Chat).
  final bool divider;
  final ValueChanged<ReminderPriority> onPriority;
  final ValueChanged<bool> onLoud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final config =
        AppScope.of(context).notifications?.priorities ??
        const PriorityConfig();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (divider) const Divider(height: 12),
        Text(
          'PRIORIDAD',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final p in ReminderPriority.values) ...[
              if (p != ReminderPriority.normal) const SizedBox(width: 6),
              Expanded(
                child: PriorityButton(
                  key: Key('priority-${p.name}'),
                  label: p.label,
                  color: priorityColor(p),
                  selected: priority == p,
                  onTap: () => onPriority(p),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _explain(priority, config),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
        InkWell(
          key: const Key('priority-loud'),
          onTap: () => onLoud(!loud),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 28,
                child: Checkbox(
                  value: loud,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => onLoud(v ?? false),
                ),
              ),
              const Icon(Icons.notifications_off_outlined, size: 16),
              const SizedBox(width: 4),
              Text(
                'Sonar aunque esté en silencio',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _explain(ReminderPriority p, PriorityConfig c) => switch (p) {
    ReminderPriority.normal => 'Avisa una vez, a la hora.',
    ReminderPriority.media =>
      'Repite cada ${c.mediaEvery} min '
          '${c.mediaInHours ? 'de ${c.mediaFrom} a ${c.mediaTo} h' : 'durante ${PriorityConfig.forLabel(c.mediaFor).toLowerCase()}'}'
          ', hasta "Hecho".',
    ReminderPriority.alta =>
      'Suena ${c.altaTimes} veces'
          '${c.altaVibrate ? ' y vibra' : ''}; repite cada ${c.altaEvery} min '
          'hasta "Hecho".',
  };
}

class PriorityButton extends StatelessWidget {
  const PriorityButton({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? color : scheme.outlineVariant,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? color : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
