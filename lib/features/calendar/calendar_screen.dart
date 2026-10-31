import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../data/reminder.dart';
import '../reminders/reminder_editor.dart';
import 'occurrences.dart';

/// Almanaque: calendario mensual con los recordatorios de cada día.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final today = dayOf(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selected = today;
  }

  void _changeMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    final today = dayOf(DateTime.now());
    _selected = today.year == _month.year && today.month == _month.month
        ? today
        : _month;
  });

  void _goToday() => setState(() {
    _selected = dayOf(DateTime.now());
    _month = DateTime(_selected.year, _selected.month);
  });

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).reminders;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showReminderEditor(context, initialDay: _selected),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: StreamBuilder<List<Reminder>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final reminders = snapshot.data ?? const [];
          final byDay = occurrencesByDay(
            reminders,
            _month,
            DateTime(_month.year, _month.month + 1),
          );
          final dayItems = byDay[_selected] ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              _MonthHeader(
                month: _month,
                onPrevious: () => _changeMonth(-1),
                onNext: () => _changeMonth(1),
                onToday: _goToday,
              ),
              const SizedBox(height: 4),
              _MonthGrid(
                month: _month,
                selected: _selected,
                counts: {
                  for (final e in byDay.entries)
                    e.key: e.value.where((o) => !_isDone(o)).length,
                },
                onSelect: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _capitalize(Fmt.day(_selected)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              if (dayItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text('Sin recordatorios este día.'),
                )
              else
                for (final o in dayItems) _OccurrenceTile(occurrence: o),
            ],
          );
        },
      ),
    );
  }

  static bool _isDone(Occurrence o) => !o.reminder.repeats && o.reminder.done;
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final title = _capitalize(DateFormat('MMMM y', Fmt.locale).format(month));
    return Row(
      children: [
        IconButton(
          tooltip: 'Mes anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
        TextButton(onPressed: onToday, child: const Text('Hoy')),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;

  /// Cantidad de recordatorios pendientes por día.
  final Map<DateTime, int> counts;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    final leading = DateTime(month.year, month.month).weekday - 1; // lunes = 0
    final days = DateTime(month.year, month.month + 1, 0).day;
    const names = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.95,
      children: [
        for (final n in names)
          Center(
            child: Text(
              n,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        for (var i = 0; i < leading; i++) const SizedBox.shrink(),
        for (var d = 1; d <= days; d++)
          _DayCell(
            day: DateTime(month.year, month.month, d),
            isToday: DateTime(month.year, month.month, d) == today,
            isSelected: DateTime(month.year, month.month, d) == selected,
            count: counts[DateTime(month.year, month.month, d)] ?? 0,
            onTap: onSelect,
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final int count;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasReminders = count > 0;
    // Hoy: bien resaltado. Días con recordatorios: fondo suave y puntitos
    // (uno por recordatorio, hasta 5). El día elegido lleva un borde.
    final bg = isToday
        ? scheme.secondary
        : hasReminders
        ? scheme.primaryContainer
        : Colors.transparent;
    final fg = isToday
        ? scheme.onSecondary
        : hasReminders
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isSelected
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(day),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  color: fg,
                  fontWeight: isToday || hasReminders ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count.clamp(0, 5); i++)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 0.75),
                        decoration: BoxDecoration(
                          color: isToday ? fg : scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OccurrenceTile extends StatelessWidget {
  const _OccurrenceTile({required this.occurrence});

  final Occurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final r = occurrence.reminder;
    final theme = Theme.of(context);
    final done = !r.repeats && r.done;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Text(
          Fmt.time(occurrence.at),
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        title: Text(
          r.title,
          style: done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: r.repeats ? Text(r.recurrence.describe(r.dueAt)) : null,
        trailing: Icon(
          done ? Icons.check_circle : (r.repeats ? Icons.repeat : null),
          color: done ? Colors.green : theme.colorScheme.onSurfaceVariant,
        ),
        onTap: () => showReminderEditor(context, reminder: r),
      ),
    );
  }
}
