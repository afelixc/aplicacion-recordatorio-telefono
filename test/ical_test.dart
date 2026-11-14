import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/core/settings.dart';
import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/features/calendar_sync/calendar_sync.dart';
import 'package:recordame/features/calendar_sync/device_calendar.dart';
import 'package:recordame/features/calendar_sync/ical.dart';

import 'calendar_sync_test.dart' show FakeCalendar;

// Como lo manda Google (renglones cortados, zona horaria, todo el día…).
const sample = '''BEGIN:VCALENDAR\r
PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
VERSION:2.0\r
X-WR-CALNAME:yo@gmail.com\r
BEGIN:VTIMEZONE\r
TZID:America/Argentina/Buenos_Aires\r
END:VTIMEZONE\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Argentina/Buenos_Aires:20261118T110000\r
DTEND;TZID=America/Argentina/Buenos_Aires:20261118T120000\r
UID:turno123@google.com\r
SUMMARY:Turno con el dentista\\, Dr. Pérez en el consultorio de la calle \r
 Belgrano\r
STATUS:CONFIRMED\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;VALUE=DATE:20261123\r
UID:feriado@google.com\r
SUMMARY:Feriado\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Argentina/Buenos_Aires:20261102T090000\r
RRULE:FREQ=WEEKLY;BYDAY=MO,TH\r
EXDATE;TZID=America/Argentina/Buenos_Aires:20261116T090000\r
UID:reunion@google.com\r
SUMMARY:Reunión de producción\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Argentina/Buenos_Aires:20261119T100000\r
UID:borrado@google.com\r
SUMMARY:Se suspendió\r
STATUS:CANCELLED\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART;TZID=America/Argentina/Buenos_Aires:20251001T100000\r
UID:viejo@google.com\r
SUMMARY:Ya pasó\r
END:VEVENT\r
END:VCALENDAR\r
''';

void main() {
  final from = DateTime(2026, 11, 14, 12);
  final to = DateTime(2027, 11, 14);

  test('lee eventos, todo el día, repetidos, borrados y renglones cortados', () {
    final events = parseIcs(sample, from: from, to: to);
    expect(events.map((e) => e.title), [
      'Turno con el dentista, Dr. Pérez en el consultorio de la calle Belgrano',
      'Reunión de producción', // jueves 19 (el lunes 16 se sacó)
      'Feriado',
    ]);
    final turno = events.first;
    expect(turno.start, DateTime(2026, 11, 18, 11));
    expect(turno.id, 'ical:turno123@google.com');
    final reunion = events[1];
    expect(reunion.start, DateTime(2026, 11, 19, 9));
    expect(reunion.repeats, isTrue);
    final feriado = events[2];
    expect(feriado.allDay, isTrue);
    expect(feriado.start, DateTime(2026, 11, 23, 9));
  });

  test('la próxima vez de uno que se repite', () {
    final start = DateTime(2026, 11, 2, 9); // lunes
    expect(
      nextOccurrence(
        start,
        'FREQ=DAILY;INTERVAL=2',
        from: DateTime(2026, 11, 5),
      ),
      DateTime(2026, 11, 6, 9),
    );
    expect(
      nextOccurrence(
        start,
        'FREQ=WEEKLY;COUNT=2',
        from: DateTime(2026, 11, 20),
      ),
      isNull,
    );
    expect(
      nextOccurrence(start, 'FREQ=MONTHLY', from: DateTime(2026, 11, 3)),
      DateTime(2026, 12, 2, 9),
    );
    expect(
      nextOccurrence(
        start,
        'FREQ=YEARLY;UNTIL=20271231T000000Z',
        from: DateTime(2026, 11, 3),
      ),
      DateTime(2027, 11, 2, 9),
    );
  });

  test('el link: arregla webcal y rechaza lo que no es', () {
    expect(
      cleanIcalUrl(
        ' webcal://calendar.google.com/calendar/ical/yo/private-abc/basic.ics ',
      ),
      'https://calendar.google.com/calendar/ical/yo/private-abc/basic.ics',
    );
    expect(cleanIcalUrl('hola'), isNull);
    expect(cleanIcalUrl('http://calendar.google.com/x.ics'), isNull);
  });

  test(
    'con el link, lo nuevo de Google llega aunque el teléfono no lo tenga',
    () async {
      final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
      await settings.load(const []);
      var events = <CalendarEvent>[];
      final sync = CalendarSync(
        calendar: FakeCalendar()..permission = false,
        settings: settings,
        icalReader: (url, from, to) async => events,
      );
      final repo = MemoryReminderRepository();
      final soon = DateTime.now().add(const Duration(days: 2));
      // "Solo lo nuevo": lo que ya estaba queda anotado como conocido.
      await settings.addCalendarKnown(['ical:viejo']);
      await settings.setIcalUrl('https://calendar.google.com/x/basic.ics');
      events = [
        CalendarEvent(id: 'ical:viejo', title: 'Viejo', start: soon),
        CalendarEvent(id: 'ical:turno', title: 'Turno', start: soon),
      ];
      expect(await sync.autoImport(repo), 1);
      expect((await repo.watchAll().first).single.title, 'Turno');
      // La segunda vez no lo repite.
      expect(await sync.autoImport(repo), 0);
      // El link se guarda cifrado (con las claves), no en las preferencias.
      expect(await settings.keys.read('ical_google'), isNotNull);
    },
  );

  test(
    'dos lecturas a la vez no lo traen dos veces; borra el repetido',
    () async {
      final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
      await settings.load(const []);
      final soon = DateTime.now().add(const Duration(days: 4));
      final sync = CalendarSync(
        calendar: FakeCalendar()..permission = false,
        settings: settings,
        icalReader: (url, from, to) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return [CalendarEvent(id: 'ical:turno', title: 'Turno', start: soon)];
        },
      );
      await settings.setIcalUrl('https://calendar.google.com/x/basic.ics');
      final repo = MemoryReminderRepository();
      await Future.wait([sync.autoImport(repo), sync.autoImport(repo)]);
      expect((await repo.watchAll().first).length, 1);

      // Uno que ya había quedado repetido (de antes del arreglo): se borra.
      final first = (await repo.watchAll().first).single;
      await repo.save(
        Reminder(
          title: first.title,
          dueAt: first.dueAt,
          calendarEventId: first.calendarEventId,
        ),
      );
      expect((await repo.watchAll().first).length, 2);
      await sync.autoImport(repo);
      expect((await repo.watchAll().first).length, 1);
    },
  );
}
