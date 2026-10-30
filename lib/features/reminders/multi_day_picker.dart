import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/recurrence.dart';

/// Lo elegido en el almanaque de varios días: o días de la semana ("todos los
/// lunes y viernes") o fechas sueltas ("el 1, el 10 y el 20"), nunca las dos
/// cosas. Lo que se toca primero manda; si después se toca del otro tipo, se
/// cambia de modo y se borra lo anterior.
class DaySelection {
  DaySelection({Set<int>? weekdays, Iterable<DateTime>? dates})
    : weekdays = {...?weekdays},
      dates = {for (final d in dates ?? const <DateTime>[]) _day(d)};

  final Set<int> weekdays;
  final Set<DateTime> dates;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get isEmpty => weekdays.isEmpty && dates.isEmpty;

  /// Devuelve true si se borraron fechas sueltas al cambiar de modo.
  bool toggleWeekday(int weekday) {
    final cleared = dates.isNotEmpty;
    dates.clear();
    if (!weekdays.remove(weekday)) weekdays.add(weekday);
    return cleared;
  }

  /// Devuelve true si se borraron días de la semana al cambiar de modo.
  bool toggleDate(DateTime date) {
    final cleared = weekdays.isNotEmpty;
    weekdays.clear();
    final d = _day(date);
    if (!dates.remove(d)) dates.add(d);
    return cleared;
  }

  bool isSelected(DateTime date) =>
      dates.contains(_day(date)) || weekdays.contains(date.weekday);

  Recurrence? toRecurrence() {
    if (weekdays.isNotEmpty) return Recurrence.weekly(weekdays);
    if (dates.isNotEmpty) return Recurrence.dates(dates);
    return null;
  }

  String describe() {
    if (weekdays.isNotEmpty) {
      return Recurrence.weekly(weekdays).describe(DateTime.now());
    }
    if (dates.isEmpty) {
      return 'Tocá los días en el almanaque o las letras de arriba.';
    }
    final sorted = dates.toList()..sort();
    final f = DateFormat('d/M', Fmt.locale);
    return '${dates.length} ${dates.length == 1 ? 'día' : 'días'}: ${sorted.map(f.format).join(', ')}';
  }
}

/// Abre el almanaque para elegir varios días. Devuelve null si se cancela.
Future<Recurrence?> showMultiDayPicker(
  BuildContext context, {
  Recurrence? initial,
  DateTime? initialMonth,
}) {
  return showModalBottomSheet<Recurrence>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MultiDayPicker(
      initial: initial,
      initialMonth: initialMonth ?? DateTime.now(),
    ),
  );
}

class MultiDayPicker extends StatefulWidget {
  const MultiDayPicker({super.key, this.initial, required this.initialMonth});

  final Recurrence? initial;
  final DateTime initialMonth;

  @override
  State<MultiDayPicker> createState() => _MultiDayPickerState();
}

class _MultiDayPickerState extends State<MultiDayPicker> {
  late DaySelection _selection;
  late DateTime _month;
  String? _notice;

  static const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _names = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábados',
    'domingos',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _selection = DaySelection(
      weekdays: r?.kind == RepeatKind.weekly ? r!.weekdays : null,
      dates: r?.kind == RepeatKind.dates ? r!.dates : null,
    );
    final first = _selection.dates.isEmpty
        ? widget.initialMonth
        : (_selection.dates.toList()..sort()).first;
    _month = DateTime(first.year, first.month);
  }

  void _toggleWeekday(int weekday) => setState(() {
    _notice = _selection.toggleWeekday(weekday)
        ? 'Cambiaste a días de la semana: se borraron las fechas sueltas.'
        : null;
  });

  void _toggleDate(DateTime date) => setState(() {
    _notice = _selection.toggleDate(date)
        ? 'Cambiaste a fechas sueltas: se borraron los días de la semana.'
        : null;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);
    final leading = DateTime(_month.year, _month.month).weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final title = DateFormat('MMMM y', Fmt.locale).format(_month);

    // En pantallas anchas el almanaque no se agranda de más, y si no entra
    // (teléfono acostado) se puede deslizar.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Elegí los días', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Tocá las letras para "todos los lunes, miércoles…", '
                  'o tocá los números para fechas sueltas.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Mes anterior',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title[0].toUpperCase() + title.substring(1),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Mes siguiente',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                    ),
                  ],
                ),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (var i = 0; i < 7; i++)
                      _Cell(
                        key: ValueKey('weekday-${i + 1}'),
                        label: _letters[i],
                        tooltip: 'Todos los ${_names[i]}',
                        selected: _selection.weekdays.contains(i + 1),
                        header: true,
                        onTap: () => _toggleWeekday(i + 1),
                      ),
                    for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                    for (var d = 1; d <= days; d++)
                      Builder(
                        builder: (_) {
                          final date = DateTime(_month.year, _month.month, d);
                          final past = date.isBefore(todayDay);
                          return _Cell(
                            key: ValueKey('day-$d'),
                            label: '$d',
                            selected: !past && _selection.isSelected(date),
                            today: date == todayDay,
                            onTap: past ? null : () => _toggleDate(date),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_notice != null)
                  Text(_notice!, style: TextStyle(color: scheme.tertiary)),
                Text(_selection.describe(), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _selection.isEmpty
                            ? null
                            : () => Navigator.pop(
                                context,
                                _selection.toRecurrence(),
                              ),
                        child: const Text('Listo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.header = false,
    this.today = false,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final bool header;
  final bool today;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = selected
        ? (header ? scheme.secondary : scheme.primary)
        : header
        ? scheme.secondaryContainer
        : Colors.transparent;
    final fg = selected
        ? (header ? scheme.onSecondary : scheme.onPrimary)
        : onTap == null
        ? scheme.onSurface.withValues(alpha: 0.3)
        : header
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    final cell = Material(
      color: bg,
      shape: header
          ? const CircleBorder()
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: today && !selected
                  ? BorderSide(color: scheme.secondary, width: 1.5)
                  : BorderSide.none,
            ),
      child: InkWell(
        customBorder: header ? const CircleBorder() : null,
        borderRadius: header ? null : BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: header || selected ? FontWeight.w700 : null,
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? cell : Tooltip(message: tooltip!, child: cell);
  }
}
