import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/drift/database.dart';
import 'package:recordame/data/drift/drift_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/features/notifications/notification_service.dart';
import 'package:recordame/features/notifications/priority_config.dart';
import 'package:recordame/features/notifications/priority_sounds.dart';
import 'package:recordame/features/settings/priorities_page.dart';

void main() {
  final ten = DateTime(2026, 11, 20, 10);

  test('media: repite cada tanto durante el tiempo elegido', () {
    const c = PriorityConfig(mediaEvery: 5, mediaFor: 60);
    final t = c.mediaRepeats(ten);
    expect(t.first, DateTime(2026, 11, 20, 10, 5));
    expect(t.last, DateTime(2026, 11, 20, 11));
    expect(t.length, 12);
  });

  test('media: en un horario, solo entre esas horas', () {
    const c = PriorityConfig(
      mediaEvery: 30,
      mediaInHours: true,
      mediaFrom: 8,
      mediaTo: 12,
    );
    final t = c.mediaRepeats(DateTime(2026, 11, 20, 7));
    expect(t.first, DateTime(2026, 11, 20, 8));
    expect(t.last, DateTime(2026, 11, 20, 12));
    // Después del horario ya no repite.
    expect(c.mediaRepeats(DateTime(2026, 11, 20, 13)), isEmpty);
  });

  test('nunca más de ${PriorityConfig.maxRepeats} repeticiones', () {
    const c = PriorityConfig(mediaEvery: 3, mediaFor: 0, altaFor: 0);
    expect(
      c.mediaRepeats(DateTime(2026, 11, 20, 0, 1)).length,
      PriorityConfig.maxRepeats,
    );
    expect(c.altaRepeats(ten).length, PriorityConfig.maxRepeats);
  });

  test('se guarda y se lee igual; lo raro vuelve a lo de siempre', () {
    const c = PriorityConfig(
      mediaEvery: 10,
      mediaSound: 'm_gotas',
      altaTimes: 15,
      altaSound: 'a_policia',
      altaFullScreen: false,
    );
    final back = PriorityConfig.decode(c.encode());
    expect(back.mediaEvery, 10);
    expect(back.mediaSoundName, 'Gotas');
    expect(back.altaTimes, 15);
    expect(back.altaSoundInfo.name, 'Sirena de policía');
    expect(back.altaFullScreen, isFalse);
    expect(PriorityConfig.decode('no es json').altaTimes, 6);
    expect(PriorityConfig.decode(null).altaSound, 'a_sirena');
  });

  test('media y alta pueden usar un sonido del teléfono', () {
    const uri = 'content://media/internal/audio/media/42';
    const c = PriorityConfig(
      mediaSound: PriorityConfig.phoneSound,
      mediaPhoneUri: uri,
      mediaPhoneName: 'Tono lindo',
      altaSound: PriorityConfig.phoneSound,
      altaPhoneUri: uri,
      altaPhoneName: 'Alarma larga',
      altaPhoneMillis: 45000,
    );
    final back = PriorityConfig.decode(c.encode());
    expect(back.mediaFromPhone, isTrue);
    expect(back.mediaSoundName, 'Tono lindo');
    expect(back.altaFromPhone, isTrue);
    expect(back.altaSoundName, 'Alarma larga');
    // Los del teléfono pueden ser largos: se toman hasta 20 segundos.
    expect(back.altaMillis, 20000);
    // Sin sonido elegido, vuelve a los de la app.
    const sinTel = PriorityConfig(altaSound: PriorityConfig.phoneSound);
    expect(sinTel.altaFromPhone, isFalse);
    expect(sinTel.altaSoundName, 'Sirena');
    // Cada sonido del teléfono tiene su canal, siempre con el mismo nombre.
    expect(
      NotificationService.soundKey(uri),
      NotificationService.soundKey(uri),
    );
    expect(
      NotificationService.soundKey(uri),
      isNot(NotificationService.soundKey('$uri/1')),
    );
  });

  test('hay 6 sonidos nuevos para media y 16 para alta', () {
    expect(mediaSounds.length, 6);
    expect(altaSounds.length, 16);
    expect(altaSounds.every((s) => s.millis > 0), isTrue);
  });

  group('cuándo repite un recordatorio', () {
    const c = PriorityConfig(mediaEvery: 5, mediaFor: 60, altaEvery: 3);

    test('normal no repite', () {
      final r = Reminder(title: 'x', dueAt: ten);
      expect(NotificationService.repeatTimes(r, c, ten), isEmpty);
    });

    test('media: las que faltan de la vez de ahora', () {
      final r = Reminder(
        title: 'x',
        dueAt: ten,
        priority: ReminderPriority.media,
      );
      final now = ten.add(const Duration(minutes: 22));
      final t = NotificationService.repeatTimes(r, c, now);
      expect(t.first, DateTime(2026, 11, 20, 10, 25));
      expect(t.last, DateTime(2026, 11, 20, 11));
    });

    test('hecho no repite', () {
      final r = Reminder(
        title: 'x',
        dueAt: ten,
        priority: ReminderPriority.alta,
        done: true,
      );
      expect(NotificationService.repeatTimes(r, c, ten), isEmpty);
    });

    test('uno diario: si hoy ya lo hizo, repite mañana', () {
      final r = Reminder(
        title: 'x',
        dueAt: DateTime(2026, 11, 1, 10),
        recurrence: const Recurrence.daily(),
        priority: ReminderPriority.media,
        lastDoneAt: ten.add(const Duration(minutes: 2)),
      );
      final now = ten.add(const Duration(minutes: 7));
      final t = NotificationService.repeatTimes(r, c, now);
      expect(t.first, DateTime(2026, 11, 21, 10, 5));
    });

    test('uno que no se repite y se pospone 1 hora: vuelve a repetir', () {
      final r = Reminder(
        title: 'x',
        // "1 hora" mueve la fecha del recordatorio.
        dueAt: ten.add(const Duration(hours: 1)),
        priority: ReminderPriority.media,
      );
      final now = ten.add(const Duration(minutes: 7));
      final t = NotificationService.repeatTimes(r, c, now);
      expect(t.first, DateTime(2026, 11, 20, 11, 5));
      expect(t.last, DateTime(2026, 11, 20, 12));
    });

    test('uno diario pospuesto a mañana: hoy se calla y mañana repite', () {
      final r = Reminder(
        title: 'x',
        dueAt: DateTime(2026, 11, 1, 10),
        recurrence: const Recurrence.daily(),
        priority: ReminderPriority.media,
        snoozedUntil: DateTime(2026, 11, 21, 10, 7),
      );
      final now = ten.add(const Duration(minutes: 7));
      final t = NotificationService.repeatTimes(r, c, now);
      // Nada más hoy.
      expect(t.every((d) => d.day == 21), isTrue);
      // Mañana repite desde la hora a la que se pospuso.
      expect(t, contains(DateTime(2026, 11, 21, 10, 12)));
      expect(t.length, lessThanOrEqualTo(PriorityConfig.maxRepeats));
    });

    test('uno diario pospuesto 1 hora: repite desde esa hora', () {
      final r = Reminder(
        title: 'x',
        dueAt: DateTime(2026, 11, 1, 10),
        recurrence: const Recurrence.daily(),
        priority: ReminderPriority.media,
        snoozedUntil: DateTime(2026, 11, 20, 11, 7),
      );
      final now = ten.add(const Duration(minutes: 7));
      final t = NotificationService.repeatTimes(r, c, now);
      expect(t.first, DateTime(2026, 11, 20, 11, 12));
      expect(t.where((d) => d.day == 20).last, DateTime(2026, 11, 20, 12, 7));
    });

    test('uno diario sin hacer: sigue repitiendo el de hoy', () {
      final r = Reminder(
        title: 'x',
        dueAt: DateTime(2026, 11, 1, 10),
        recurrence: const Recurrence.daily(),
        priority: ReminderPriority.media,
      );
      final now = ten.add(const Duration(minutes: 7));
      final t = NotificationService.repeatTimes(r, c, now);
      expect(t.first, DateTime(2026, 11, 20, 10, 10));
    });
  });

  test('la base guarda la prioridad y "sonar en silencio"', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftReminderRepository(db);
    final r = await repo.save(
      Reminder(
        title: 'Pastilla',
        dueAt: ten,
        priority: ReminderPriority.alta,
        loud: true,
      ),
    );
    final back = (await repo.getById(r.id!))!;
    expect(back.priority, ReminderPriority.alta);
    expect(back.loud, isTrue);
    await db.close();
  });

  testWidgets('Configuración: tres ventanitas que abren cada prioridad', (
    tester,
  ) async {
    final service = NotificationService.instance;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PrioritiesSection(service: service),
          ),
        ),
      ),
    );
    expect(find.text('Prioridades de notificaciones'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Alta'), findsOneWidget);
    expect(find.text('Sonar en modo silencio'), findsOneWidget);
    expect(find.text('HECHO'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prio-alta')));
    await tester.pumpAndSettle();
    expect(find.text('Prioridad alta'), findsOneWidget);
    expect(find.text('Cuántas veces suena seguido'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pitido urgente'), 200);
    expect(find.text('Sirena de policía'), findsOneWidget);
    // Abajo de todo: elegir un sonido del teléfono.
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('alta-phone')), findsOneWidget);
    expect(find.text('Elegir un sonido del teléfono…'), findsOneWidget);
  });
}
