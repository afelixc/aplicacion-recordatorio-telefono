import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:recordame/app.dart';
import 'package:recordame/core/settings.dart';
import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/features/calendar_sync/calendar_sync.dart';
import 'package:recordame/features/calendar_sync/device_calendar.dart';
import 'package:recordame/features/settings/battery_help.dart';

/// Un calendario de mentira, en memoria.
class FakeCalendar implements DeviceCalendar {
  bool permission = true;
  int _next = 100;
  final stored =
      <String, ({String cal, String title, DateTime start, String? rrule})>{};

  void add(String id, String title, DateTime start) =>
      stored[id] = (cal: '1', title: title, start: start, rrule: null);

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> requestPermission() async => permission = true;
  @override
  Future<List<PhoneCalendar>> calendars() async => const [
    PhoneCalendar(
      id: '1',
      name: 'yo@gmail.com',
      account: 'yo@gmail.com',
      primary: true,
    ),
    PhoneCalendar(id: '2', name: 'Trabajo', account: 'yo@gmail.com'),
  ];
  @override
  Future<List<CalendarEvent>> events(
    String c,
    DateTime from,
    DateTime to,
  ) async => [
    for (final e in stored.entries)
      if (e.value.cal == c &&
          !e.value.start.isBefore(from) &&
          !e.value.start.isAfter(to))
        CalendarEvent(
          id: e.key,
          title: e.value.title,
          start: e.value.start,
          repeats: e.value.rrule != null,
        ),
  ];
  @override
  Future<String?> create(
    String c,
    String title,
    DateTime start,
    String? rrule,
  ) async {
    final id = '${_next++}';
    stored[id] = (cal: c, title: title, start: start, rrule: rrule);
    return id;
  }

  @override
  Future<bool> update(
    String id,
    String title,
    DateTime start,
    String? rrule,
  ) async {
    final old = stored[id];
    if (old == null) return false;
    stored[id] = (cal: old.cal, title: title, start: start, rrule: rrule);
    return true;
  }

  @override
  Future<void> delete(String id) async => stored.remove(id);
  bool background = false;
  @override
  Future<void> scheduleBackground() async => background = true;
  @override
  Future<void> cancelBackground() async => background = false;
}

Future<
  (CalendarSync, CalendarSyncRepository, FakeCalendar, MemoryReminderRepository)
>
make({List<Reminder> initial = const []}) async {
  final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
  await settings.load(['claude']);
  final cal = FakeCalendar();
  final sync = CalendarSync(calendar: cal, settings: settings);
  final inner = MemoryReminderRepository(initial);
  return (sync, CalendarSyncRepository(inner, sync), cal, inner);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_AR'));
  final later = DateTime.now().add(const Duration(days: 3));
  final at = DateTime(later.year, later.month, later.day, 10);

  test('reglas de repetición para el calendario', () {
    Reminder r(Recurrence rec) =>
        Reminder(title: 'x', dueAt: DateTime(2026, 11, 15, 9), recurrence: rec);
    expect(rruleFor(r(const Recurrence.none())), isNull);
    expect(rruleFor(r(const Recurrence.daily())), 'FREQ=DAILY');
    expect(rruleFor(r(Recurrence.weekly({1, 4}))), 'FREQ=WEEKLY;BYDAY=MO,TH');
    expect(
      rruleFor(r(const Recurrence.monthly())),
      'FREQ=MONTHLY;BYMONTHDAY=15',
    );
    expect(rruleFor(r(const Recurrence.yearly())), 'FREQ=YEARLY');
  });

  test('apagado: el calendario no se toca', () async {
    final (_, repo, cal, _) = await make();
    await repo.save(Reminder(title: 'Luz', dueAt: at));
    expect(cal.stored, isEmpty);
  });

  test('enviar: crea, actualiza sin duplicar y borra', () async {
    final (sync, repo, cal, _) = await make();
    await sync.settings.setCalendar('1', 'yo');
    await sync.settings.setCalendarSend(true);
    var r = await repo.save(Reminder(title: 'Luz', dueAt: at));
    expect(cal.stored.values.single.title, 'Luz');
    expect(r.calendarEventId, isNotNull);

    r = await repo.save(r.copyWith(title: 'Pagar la luz'));
    expect(cal.stored.values.single.title, 'Pagar la luz');

    await repo.delete(r.id!);
    expect(cal.stored, isEmpty);
  });

  test('días puntuales: un evento por día', () async {
    final (sync, repo, cal, _) = await make();
    await sync.settings.setCalendar('1', 'yo');
    await sync.settings.setCalendarSend(true);
    final r = await repo.save(
      Reminder(
        title: 'Guitarra',
        dueAt: DateTime(2026, 11, 5, 18),
        recurrence: Recurrence.dates([
          DateTime(2026, 11, 5),
          DateTime(2026, 11, 12),
        ]),
      ),
    );
    expect(cal.stored.length, 2);
    expect(r.calendarEventId!.split(',').length, 2);
  });

  test('mandar también los que ya tenía', () async {
    final (sync, repo, cal, _) = await make(
      initial: [
        Reminder(title: 'Uno', dueAt: at),
        Reminder(title: 'Hecho', dueAt: at, done: true),
      ],
    );
    await sync.settings.setCalendar('1', 'yo');
    await sync.settings.setCalendarSend(true);
    expect(await sync.sendExisting(repo), 1);
    expect(cal.stored.values.single.title, 'Uno');
  });

  test(
    'traer del calendario: no repite ni lo devuelve al calendario',
    () async {
      final (sync, repo, cal, inner) = await make();
      await sync.settings.setCalendar('1', 'yo');
      await sync.settings.setCalendarSend(true);
      cal.add('7', 'Dentista', at);
      final events = await sync.upcoming(const Duration(days: 30));
      expect(await sync.import(events, repo), 1);
      expect(await sync.import(events, repo), 0);
      expect((await inner.watchAll().first).single.calendarEventId, '7');
      expect(cal.stored.length, 1, reason: 'no se duplica en el calendario');
    },
  );

  test('traer lo nuevo automáticamente: solo lo anotado después', () async {
    final (sync, repo, cal, inner) = await make();
    await sync.settings.setCalendar('1', 'yo');
    cal.add('1', 'Viejo', at);
    await sync.startAuto();
    expect(
      cal.background,
      isTrue,
      reason: 'sigue revisando con la app cerrada',
    );
    expect(await sync.autoImport(repo), 0);
    cal.add('2', 'Nuevo desde la compu', at.add(const Duration(hours: 2)));
    expect(await sync.autoImport(repo), 1);
    expect(await sync.autoImport(repo), 0);
    expect((await inner.watchAll().first).single.title, 'Nuevo desde la compu');
  });

  testWidgets('pantalla: permiso, enviar con Cancelar y traer marcados', (
    tester,
  ) async {
    final (sync, repo, cal, _) = await make(
      initial: [Reminder(title: 'Uno', dueAt: at)],
    );
    cal.permission = false;
    cal.add('7', 'Dentista', at.add(const Duration(days: 1)));
    cal.add('8', 'Asado', at.add(const Duration(days: 2)));
    await tester.pumpWidget(
      RecordameApp(reminders: repo, settings: sync.settings, calendar: sync),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Google Calendar'), 100);
    await tester.tap(find.text('Google Calendar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cal-permission')));
    await tester.pumpAndSettle();
    expect(sync.settings.calendarId, '1', reason: 'elige el principal');

    // Prender "enviar" y cancelar: queda apagado.
    await tester.tap(find.byKey(const Key('cal-send')));
    await tester.pumpAndSettle();
    expect(find.text('Mandar también esos 1'), findsOneWidget);
    await tester.tap(find.text('Cancelar (no enviar nada)'));
    await tester.pumpAndSettle();
    expect(sync.settings.calendarSend, isFalse);

    // Prender y mandar los que ya tenía.
    await tester.tap(find.byKey(const Key('cal-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mandar también esos 1'));
    await tester.pumpAndSettle();
    expect(sync.settings.calendarSend, isTrue);
    expect(cal.stored.values.map((e) => e.title), contains('Uno'));

    // Traer: marcar el dentista y agregar.
    await tester.ensureVisible(find.text('Dentista'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dentista'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cal-add')));
    await tester.tap(find.byKey(const Key('cal-add')));
    await tester.pumpAndSettle();
    final titles = (await repo.watchAll().first).map((r) => r.title);
    expect(titles, containsAll(['Uno', 'Dentista']));
    expect(titles, isNot(contains('Asado')));
  });

  testWidgets('batería: explica para qué sirve y se pone verde', (
    tester,
  ) async {
    var free = false;
    await tester.pumpWidget(
      MaterialApp(home: BatteryHelpPage(check: () async => free)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Android puede frenar a Recordame'), findsOneWidget);
    expect(
      find.textContaining('Google Calendar con la app cerrada'),
      findsOneWidget,
    );
    expect(find.text('Samsung', skipOffstage: false), findsOneWidget);
    free = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Listo ✓ Sin restricciones'), findsOneWidget);
  });
}
