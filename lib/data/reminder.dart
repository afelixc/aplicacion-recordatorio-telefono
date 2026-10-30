/// Un recordatorio.
class Reminder {
  const Reminder({
    this.id,
    required this.title,
    required this.dueAt,
    this.done = false,
    this.completedAt,
    this.calendarEventId,
  });

  /// Null mientras no se guardó.
  final int? id;
  final String title;
  final DateTime dueAt;
  final bool done;
  final DateTime? completedAt;

  /// Id del evento en Google Calendar (segunda etapa; por ahora siempre null).
  final String? calendarEventId;

  Reminder copyWith({
    int? id,
    String? title,
    DateTime? dueAt,
    bool? done,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      dueAt: dueAt ?? this.dueAt,
      done: done ?? this.done,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      calendarEventId: calendarEventId,
    );
  }
}
