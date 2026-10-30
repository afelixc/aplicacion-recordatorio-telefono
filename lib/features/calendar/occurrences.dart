import '../../data/reminder.dart';

/// Una vez que toca un recordatorio (en uno que se repite, cada repetición).
class Occurrence {
  const Occurrence(this.reminder, this.at);

  final Reminder reminder;
  final DateTime at;
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Todas las veces que tocan los recordatorios entre [from] (incluido) y
/// [to] (excluido), agrupadas por día y ordenadas por hora.
Map<DateTime, List<Occurrence>> occurrencesByDay(
  List<Reminder> reminders,
  DateTime from,
  DateTime to,
) {
  final result = <DateTime, List<Occurrence>>{};
  void add(Reminder r, DateTime at) =>
      result.putIfAbsent(dayOf(at), () => []).add(Occurrence(r, at));

  for (final r in reminders) {
    if (!r.repeats) {
      if (!r.dueAt.isBefore(from) && r.dueAt.isBefore(to)) add(r, r.dueAt);
      continue;
    }
    // Los que se dejaron de repetir no se muestran.
    if (r.done) continue;
    var cursor = from.subtract(const Duration(microseconds: 1));
    while (true) {
      final next = r.recurrence.nextAfter(r.dueAt, cursor);
      if (next == null || !next.isBefore(to)) break;
      add(r, next);
      cursor = next;
    }
  }
  for (final list in result.values) {
    list.sort((a, b) => a.at.compareTo(b.at));
  }
  return result;
}
