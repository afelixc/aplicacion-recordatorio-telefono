import '../../core/settings.dart';
import '../../data/recurrence.dart';
import '../../data/reminder.dart';
import '../../data/reminder_repository.dart';
import 'device_calendar.dart';
import 'ical.dart';

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

typedef IcalReader = Future<List<CalendarEvent>> Function(
  String url,
  DateTime from,
  DateTime to,
);

/// Une Recordame con el calendario que ya está en el teléfono.
class CalendarSync {
  CalendarSync({
    required this.calendar,
    required this.settings,
    IcalReader? icalReader,
  }) : icalReader = icalReader ?? _readIcal;

  final DeviceCalendar calendar;
  final AppSettings settings;

  /// Lee el link privado de Google (en las pruebas, uno de mentira).
  final IcalReader icalReader;

  static Future<List<CalendarEvent>> _readIcal(
    String url,
    DateTime from,
    DateTime to,
  ) => fetchIcal(url, from: from, to: to);

  /// Lo del link privado de Google, de ahora a [window].
  Future<List<CalendarEvent>> icalUpcoming(Duration window, {DateTime? now}) {
    now ??= DateTime.now();
    return icalReader(settings.icalUrl!, now, now.add(window));
  }

  bool get sending => settings.calendarSend && settings.calendarId != null;

  /// Cambiar de calendario. Por seguridad apaga "enviar" (2) y "traer lo
  /// nuevo" (4): si se tocó el equivocado no pasa nada hasta volver a
  /// prenderlos (y confirmar mirando el nombre). Lo ya enviado queda en el
  /// calendario anterior y sus cambios siguen yendo ahí. Devuelve si apagó
  /// alguno.
  Future<bool> choose(PhoneCalendar c) async {
    if (c.id == settings.calendarId) return false;
    await settings.setCalendar(c.id, c.label);
    final wasOn = settings.calendarSend || settings.calendarAuto;
    if (settings.calendarSend) await settings.setCalendarSend(false);
    if (settings.calendarAuto) await stopAuto();
    return wasOn;
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
    for (final e in events) {
      // Se mira de nuevo cada vez: otra lectura pudo haberlo traído recién.
      final have = await repo.watchAll().first;
      if (alreadyHave(e, have)) continue;
      await repo.save(
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
  /// Si está apagado, se cancela (por si quedó programada de antes).
  Future<void> ensureBackground() async {
    if (settings.calendarAuto || settings.icalUrl != null) {
      await calendar.scheduleBackground();
    } else {
      await calendar.cancelBackground();
    }
  }

  /// Trae lo nuevo del calendario (al abrir o volver a la app). Si ya hay una
  /// lectura en marcha, espera esa: dos a la vez traían lo mismo dos veces.
  Future<int> autoImport(ReminderRepository repo) =>
      _importing ??= _autoImport(repo).whenComplete(() => _importing = null);

  Future<int>? _importing;

  Future<int> _autoImport(ReminderRepository repo) async {
    await removeDuplicates(repo);
    final events = <CalendarEvent>[];
    if (settings.calendarAuto &&
        settings.calendarId != null &&
        await calendar.hasPermission()) {
      events.addAll(await upcoming(autoWindow));
    }
    // El link privado de Google: lo nuevo llega aunque el teléfono no lo
    // reciba. Si no hay internet, se intenta la próxima vez.
    if (settings.icalUrl != null) {
      try {
        final now = DateTime.now();
        final fromLink = await icalUpcoming(autoWindow, now: now);
        events.addAll(fromLink);
        // Solo si Google contestó bien: lo borrado o cambiado allá, también
        // acá.
        await followLink(repo, fromLink, now: now);
      } catch (_) {}
    }
    if (events.isEmpty) return 0;
    final fresh = <String, CalendarEvent>{};
    for (final e in events) {
      if (!settings.calendarKnown.contains(e.id)) {
        fresh.putIfAbsent(e.id, () => e);
      }
    }
    // Se anotan como conocidos antes de traerlos: si otra lectura (la de la
    // app cerrada) empieza mientras tanto, no los vuelve a traer.
    await settings.addCalendarKnown(events.map((e) => e.id));
    return import(fresh.values, repo);
  }

  /// Lo que vino del link y todavía no pasó: si en Google lo borraron, se
  /// borra de Recordame; si le cambiaron el nombre o la hora, se cambia acá.
  /// Los hechos y los ya pasados no se tocan.
  Future<({int removed, int changed})> followLink(
    ReminderRepository repo,
    List<CalendarEvent> fromLink, {
    DateTime? now,
  }) async {
    now ??= DateTime.now();
    final byId = {for (final e in fromLink) e.id: e};
    final until = now.add(autoWindow);
    var removed = 0;
    var changed = 0;
    for (final r in await repo.watchAll().first) {
      final id = r.calendarEventId;
      if (!isLinkId(id) || r.done || r.id == null) continue;
      if (r.dueAt.isBefore(now) || !r.dueAt.isBefore(until)) continue;
      final e = byId[id];
      if (e == null) {
        await repo.delete(r.id!);
        removed++;
        continue;
      }
      final title = e.title.trim().isEmpty
          ? 'Evento del calendario'
          : e.title.trim();
      if (r.title != title || r.dueAt != e.start) {
        await repo.save(
          r.copyWith(title: title, dueAt: e.start, clearSnoozedUntil: true),
        );
        changed++;
      }
    }
    return (removed: removed, changed: changed);
  }

  /// Borra los repetidos que trajo el link de Google (mismo evento dos
  /// veces). Deja el primero. No toca el calendario.
  Future<int> removeDuplicates(ReminderRepository repo) async {
    final seen = <String>{};
    var removed = 0;
    final all = (await repo.watchAll().first).toList()
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    for (final r in all) {
      final id = r.calendarEventId;
      if (id == null || !isLinkId(id)) continue;
      if (!seen.add(id) && r.id != null) {
        await repo.delete(r.id!);
        removed++;
      }
    }
    return removed;
  }
}

/// Lo que vino del link privado de Google (no es un evento del teléfono).
bool isLinkId(String? id) => id != null && id.startsWith('ical:');

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
    // Lo que vino del link de Google ya está en Google: no se manda otra vez.
    if (isLinkId(saved.calendarEventId)) return saved;
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
    if (r == null || !sync.sending || isLinkId(r.calendarEventId)) return;
    try {
      await sync.remove(r);
    } catch (_) {}
  }
}
