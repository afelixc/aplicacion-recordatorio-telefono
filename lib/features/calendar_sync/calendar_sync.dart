import '../../core/settings.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_repository.dart';
import 'device_calendar.dart';

/// Regla de repetición del calendario (RRULE) para un recordatorio. Null si
/// no se repite o si son días puntuales (esos van como eventos sueltos).
String? rruleFor(Reminder r) {
  const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  final rec = r.recurrence;
  return switch (rec.kind) {
    RepeatKind.none || RepeatKind.dates => null,
    RepeatKind.daily => 'FREQ=DAILY',
    RepeatKind.weekly =>
      'FREQ=WEEKLY;BYDAY=${(rec.weekdays.isEmpty ? {r.dueAt.weekday} : rec.weekdays).toList().map((d) => days[d - 1]).join(',')}',
    RepeatKind.monthly => 'FREQ=MONTHLY;BYMONTHDAY=${r.dueAt.day}',
    RepeatKind.yearly => 'FREQ=YEARLY',
  };
}

/// Si un evento del calendario ya está en Recordame.
bool alreadyHave(CalendarEvent e, List<Reminder> reminders) => reminders.any(
  (r) =>
      (r.calendarEventId?.split(',').contains(e.id) ?? false) ||
      (r.title.trim().toLowerCase() == e.title.trim().toLowerCase() &&
          r.dueAt.year == e.start.year &&
          r.dueAt.month == e.start.month &&
          r.dueAt.day == e.start.day &&
          r.dueAt.hour == e.start.hour &&
          r.dueAt.minute == e.start.minute),
);

/// Une Recordame con el calendario que ya está en el teléfono.
class CalendarSync {
  CalendarSync({required this.calendar, required this.settings});

  final DeviceCalendar calendar;
  final AppSettings settings;

  bool get sending => settings.calendarSend && settings.calendarId != null;

  /// Cambiar de calendario. Lo ya enviado queda en el calendario anterior
  /// (y sus cambios siguen yendo ahí); lo nuevo va al elegido. Si "traer lo
  /// nuevo" está prendido, lo que ya tiene el elegido no se trae de golpe.
  Future<void> choose(PhoneCalendar c) async {
    await settings.setCalendar(c.id, c.label);
    if (!c.writable && settings.calendarSend) {
      await settings.setCalendarSend(false);
    }
    if (settings.calendarAuto) {
      try {
        await settings.addCalendarKnown(
          (await upcoming(autoWindow)).map((e) => e.id),
        );
      } catch (_) {}
    }
  }

  // --- De Recordame → al calendario ---

  /// Crea o actualiza el evento; devuelve el id (o ids) para guardar.
  Future<String?> push(Reminder r) async {
    final cal = settings.calendarId!;
    final ids = r.calendarEventId?.split(',') ?? const <String>[];
    if (r.recurrence.kind == RepeatKind.dates) {
      for (final id in ids) {
        await calendar.delete(id);
      }
      final created = <String>[];
      for (final d in r.recurrence.dates) {
        final at = DateTime(
          d.year,
          d.month,
          d.day,
          r.dueAt.hour,
          r.dueAt.minute,
        );
        final id = await calendar.create(cal, r.title, at, null);
        if (id != null) created.add(id);
      }
      return created.isEmpty ? null : created.join(',');
    }
    final rrule = rruleFor(r);
    if (ids.length == 1 &&
        await calendar.update(ids.first, r.title, r.dueAt, rrule)) {
      return ids.first;
    }
    for (final id in ids) {
      await calendar.delete(id);
    }
    return calendar.create(cal, r.title, r.dueAt, rrule);
  }

  Future<void> remove(Reminder r) async {
    for (final id in r.calendarEventId?.split(',') ?? const <String>[]) {
      await calendar.delete(id);
    }
  }

  /// Manda al calendario los pendientes que todavía no están.
  Future<int> sendExisting(ReminderRepository repo) async {
    var sent = 0;
    for (final r in await repo.watchAll().first) {
      if (r.done || r.calendarEventId != null) continue;
      await repo.save(r); // el repositorio lo manda al calendario
      sent++;
    }
    return sent;
  }

  // --- Del calendario → a Recordame ---

  static const autoWindow = Duration(days: 365);

  Future<List<CalendarEvent>> upcoming(Duration window, {DateTime? now}) {
    now ??= DateTime.now();
    return calendar.events(settings.calendarId!, now, now.add(window));
  }

  /// Agrega a Recordame los eventos elegidos.
  Future<int> import(
    Iterable<CalendarEvent> events,
    ReminderRepository repo,
  ) async {
    var added = 0;
    final have = await repo.watchAll().first;
    for (final e in events) {
      if (alreadyHave(e, have)) continue;
      final saved = await repo.save(
        Reminder(
          title: e.title.trim().isEmpty
              ? 'Evento del calendario'
              : e.title.trim(),
          dueAt: e.start,
          // Los que se repiten se traen como una sola vez: no se ata el
          // evento entero a este recordatorio.
          calendarEventId: e.repeats ? null : e.id,
        ),
      );
      have.add(saved);
      added++;
    }
    return added;
  }

  /// Al prender "Traer lo nuevo automáticamente": lo que ya está en el
  /// calendario no se trae, solo lo que se anote de ahora en más.
  Future<void> startAuto() async {
    final ids = (await upcoming(autoWindow)).map((e) => e.id);
    await settings.setCalendarAuto(true, known: ids);
    await calendar.scheduleBackground();
  }

  Future<void> stopAuto() async {
    await settings.setCalendarAuto(false);
    await calendar.cancelBackground();
  }

  /// Al abrir la app: si está prendido, que siga revisando con la app cerrada.
  Future<void> ensureBackground() async {
    if (settings.calendarAuto) await calendar.scheduleBackground();
  }

  /// Trae lo nuevo del calendario (al abrir o volver a la app).
  Future<int> autoImport(ReminderRepository repo) async {
    if (!settings.calendarAuto || settings.calendarId == null) return 0;
    if (!await calendar.hasPermission()) return 0;
    final events = await upcoming(autoWindow);
    final fresh = <String, CalendarEvent>{};
    for (final e in events) {
      if (!settings.calendarKnown.contains(e.id)) {
        fresh.putIfAbsent(e.id, () => e);
      }
    }
    final added = await import(fresh.values, repo);
    await settings.addCalendarKnown(events.map((e) => e.id));
    return added;
  }
}

/// Envuelve otro repositorio: si está prendido "Enviar al calendario", cada
/// cambio se refleja en el calendario del teléfono. Si el calendario falla,
/// el recordatorio igual se guarda.
class CalendarSyncRepository implements ReminderRepository {
  CalendarSyncRepository(this._inner, this.sync);

  final ReminderRepository _inner;
  final CalendarSync sync;

  @override
  Stream<List<Reminder>> watchAll() => _inner.watchAll();

  @override
  Future<Reminder?> getById(int id) => _inner.getById(id);

  static bool _same(Reminder a, Reminder b) =>
      a.title == b.title &&
      a.dueAt == b.dueAt &&
      a.recurrence.storageKind == b.recurrence.storageKind &&
      a.recurrence.storageWeekdays == b.recurrence.storageWeekdays &&
      a.recurrence.storageDates == b.recurrence.storageDates &&
      a.done == b.done;

  @override
  Future<Reminder> save(Reminder reminder) async {
    final previous = reminder.id == null
        ? null
        : await _inner.getById(reminder.id!);
    // "Deshacer" después de borrar: su evento ya se borró, se crea otro.
    if (reminder.id != null && previous == null) {
      reminder = reminder.copyWith(clearCalendarEventId: true);
    }
    var saved = await _inner.save(reminder);
    if (!sync.sending || saved.done) return saved;
    final unchanged =
        saved.calendarEventId != null &&
        (previous == null || _same(previous, saved));
    if (unchanged) return saved;
    try {
      final id = await sync.push(saved);
      if (id != saved.calendarEventId) {
        saved = await _inner.save(
          saved.copyWith(calendarEventId: id, clearCalendarEventId: id == null),
        );
      }
    } catch (_) {
      // Sin permiso o calendario borrado: queda solo en Recordame.
    }
    return saved;
  }

  @override
  Future<void> setDone(int id, bool done) => _inner.setDone(id, done);

  @override
  Future<void> delete(int id) async {
    final r = await _inner.getById(id);
    await _inner.delete(id);
    if (r == null || !sync.sending) return;
    try {
      await sync.remove(r);
    } catch (_) {}
  }
}
