import 'package:intl/intl.dart';

/// Cada cuánto se repite un recordatorio.
enum RepeatKind { none, daily, weekly, monthly, yearly, dates }

/// Regla de repetición. La hora (y el día del mes o del año) salen de la fecha
/// del recordatorio; acá se guardan los días de la semana o las fechas sueltas.
class Recurrence {
  const Recurrence.none()
    : kind = RepeatKind.none,
      weekdays = const {},
      dates = const [];
  const Recurrence.daily()
    : kind = RepeatKind.daily,
      weekdays = const {},
      dates = const [];
  const Recurrence.monthly()
    : kind = RepeatKind.monthly,
      weekdays = const {},
      dates = const [];
  const Recurrence.yearly()
    : kind = RepeatKind.yearly,
      weekdays = const {},
      dates = const [];

  /// [weekdays] usa los números de [DateTime.monday] (1) a [DateTime.sunday] (7).
  Recurrence.weekly(Set<int> weekdays)
    : kind = RepeatKind.weekly,
      weekdays = Set.unmodifiable(weekdays),
      dates = const [];

  /// Fechas sueltas (se usa solo el día; la hora es la del recordatorio).
  Recurrence.dates(Iterable<DateTime> dates)
    : kind = RepeatKind.dates,
      weekdays = const {},
      dates = List.unmodifiable(
        {for (final d in dates) DateTime(d.year, d.month, d.day)}.toList()
          ..sort(),
      );

  final RepeatKind kind;
  final Set<int> weekdays;
  final List<DateTime> dates;

  bool get repeats => kind != RepeatKind.none;

  /// Próxima vez que toca, estrictamente después de [after].
  /// [start] es la fecha y hora del recordatorio. Null si ya no hay más.
  DateTime? nextAfter(DateTime start, DateTime after) {
    DateTime at(int y, int m, int d) =>
        DateTime(y, m, d, start.hour, start.minute);
    // Nunca antes de la fecha de inicio.
    if (kind != RepeatKind.dates && after.isBefore(start)) {
      after = start.subtract(const Duration(microseconds: 1));
    }

    switch (kind) {
      case RepeatKind.none:
        return start.isAfter(after) ? start : null;

      case RepeatKind.daily:
        var c = at(after.year, after.month, after.day);
        if (!c.isAfter(after)) c = at(after.year, after.month, after.day + 1);
        return c;

      case RepeatKind.weekly:
        final days = weekdays.isEmpty ? {start.weekday} : weekdays;
        for (var i = 0; i <= 7; i++) {
          final c = at(after.year, after.month, after.day + i);
          if (days.contains(c.weekday) && c.isAfter(after)) return c;
        }
        return null;

      case RepeatKind.monthly:
        for (var i = 0; i <= 12; i++) {
          final y = after.year, m = after.month + i;
          final c = at(y, m, _clampDay(y, m, start.day));
          if (c.isAfter(after)) return c;
        }
        return null;

      case RepeatKind.yearly:
        for (var i = 0; i <= 1; i++) {
          final y = after.year + i;
          final c = at(y, start.month, _clampDay(y, start.month, start.day));
          if (c.isAfter(after)) return c;
        }
        return null;

      case RepeatKind.dates:
        for (final d in dates) {
          final c = at(d.year, d.month, d.day);
          if (c.isAfter(after)) return c;
        }
        return null;
    }
  }

  /// Las próximas [count] veces a partir de [after].
  List<DateTime> upcoming(DateTime start, DateTime after, int count) {
    final result = <DateTime>[];
    var cursor = after;
    while (result.length < count) {
      final next = nextAfter(start, cursor);
      if (next == null) break;
      result.add(next);
      cursor = next;
    }
    return result;
  }

  /// Texto para mostrar, por ejemplo "Todos los lunes y miércoles".
  String describe(DateTime start) {
    const locale = 'es_AR';
    switch (kind) {
      case RepeatKind.none:
        return 'No se repite';
      case RepeatKind.daily:
        return 'Todos los días';
      case RepeatKind.weekly:
        final days = (weekdays.isEmpty ? {start.weekday} : weekdays).toList()
          ..sort();
        if (days.length == 7) return 'Todos los días';
        // 2026-11-02 es lunes: sirve para sacar el nombre de cada día.
        final names = [
          for (final d in days)
            DateFormat.EEEE(locale).format(DateTime(2026, 11, 1 + d)),
        ];
        return 'Todos los ${_joinList(names.map(_plural).toList())}';
      case RepeatKind.monthly:
        return 'Todos los meses, el día ${start.day}';
      case RepeatKind.yearly:
        return 'Todos los años, el ${DateFormat("d 'de' MMMM", locale).format(start)}';
      case RepeatKind.dates:
        final f = DateFormat('d/M', locale);
        return 'Días: ${dates.map(f.format).join(', ')}';
    }
  }

  static String _plural(String day) =>
      day.endsWith('s') ? day : '${day}s'; // lunes → lunes, sábado → sábados

  static String _joinList(List<String> items) => items.length <= 1
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';

  static int _clampDay(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return day > last ? last : day;
  }

  // --- Guardado en la base ---

  String get storageKind => kind.name;

  int get storageWeekdays =>
      weekdays.fold(0, (mask, d) => mask | (1 << (d - 1)));

  String? get storageDates => kind == RepeatKind.dates
      ? dates.map((d) => DateFormat('yyyy-MM-dd').format(d)).join(',')
      : null;

  static Recurrence fromStorage(String kind, int weekdayMask, String? dates) {
    switch (RepeatKind.values.asNameMap()[kind] ?? RepeatKind.none) {
      case RepeatKind.none:
        return const Recurrence.none();
      case RepeatKind.daily:
        return const Recurrence.daily();
      case RepeatKind.weekly:
        return Recurrence.weekly({
          for (var d = 1; d <= 7; d++)
            if (weekdayMask & (1 << (d - 1)) != 0) d,
        });
      case RepeatKind.monthly:
        return const Recurrence.monthly();
      case RepeatKind.yearly:
        return const Recurrence.yearly();
      case RepeatKind.dates:
        return Recurrence.dates([
          for (final s in (dates ?? '').split(','))
            if (s.isNotEmpty) DateTime.parse(s),
        ]);
    }
  }
}
