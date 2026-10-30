import 'recurrence.dart';

/// Un recordatorio.
class Reminder {
  const Reminder({
    this.id,
    required this.title,
    required this.dueAt,
    this.recurrence = const Recurrence.none(),
    this.done = false,
    this.completedAt,
    this.lastDoneAt,
    this.snoozedUntil,
    this.calendarEventId,
  });

  /// Null mientras no se guardó.
  final int? id;
  final String title;

  /// Fecha y hora. Si se repite, es la primera vez y de acá sale la hora.
  final DateTime dueAt;
  final Recurrence recurrence;

  /// En uno que se repite, "hecho" significa que ya no se repite más.
  final bool done;
  final DateTime? completedAt;

  /// Última vez que se tocó "Hecho" en uno que se repite.
  final DateTime? lastDoneAt;

  /// Aviso pospuesto de uno que se repite (en los que no se repiten se mueve [dueAt]).
  final DateTime? snoozedUntil;

  /// Id del evento en Google Calendar (segunda etapa; por ahora siempre null).
  final String? calendarEventId;

  bool get repeats => recurrence.repeats;

  /// Próxima vez que toca después de [now], o null si ya no hay más.
  DateTime? nextOccurrence([DateTime? now]) {
    if (done) return null;
    return recurrence.nextAfter(dueAt, now ?? DateTime.now());
  }

  Reminder copyWith({
    int? id,
    String? title,
    DateTime? dueAt,
    Recurrence? recurrence,
    bool? done,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? lastDoneAt,
    DateTime? snoozedUntil,
    bool clearSnoozedUntil = false,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      dueAt: dueAt ?? this.dueAt,
      recurrence: recurrence ?? this.recurrence,
      done: done ?? this.done,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      lastDoneAt: lastDoneAt ?? this.lastDoneAt,
      snoozedUntil: clearSnoozedUntil
          ? null
          : snoozedUntil ?? this.snoozedUntil,
      calendarEventId: calendarEventId,
    );
  }
}
