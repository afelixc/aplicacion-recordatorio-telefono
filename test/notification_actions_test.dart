import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/memory_reminder_repository.dart';
import 'package:recordame/data/reminder.dart';
import 'package:recordame/data/scheduling_reminder_repository.dart';
import 'package:recordame/features/notifications/reminder_actions.dart';
import 'package:recordame/features/notifications/reminder_scheduler.dart';
import 'package:recordame/features/notifications/snooze_options.dart';

/// Anota qué avisos quedarían programados.
class FakeScheduler implements ReminderScheduler {
  final scheduled = <int, DateTime>{};

  @override
  Future<void> schedule(Reminder r) async {
    scheduled.remove(r.id);
    if (!r.done && r.dueAt.isAfter(DateTime.now())) scheduled[r.id!] = r.dueAt;
  }

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    scheduled.clear();
    for (final r in reminders) {
      await schedule(r);
    }
  }
}

void main() {
  late FakeScheduler scheduler;
  late SchedulingReminderRepository repo;
  late ReminderActions actions;
  final tomorrow = DateTime.now().add(const Duration(days: 1));

  setUp(() {
    scheduler = FakeScheduler();
    repo = SchedulingReminderRepository(MemoryReminderRepository(), scheduler);
    actions = ReminderActions(repo);
  });

  test('guardar programa el aviso; hecho y borrar lo cancelan', () async {
    final r = await repo.save(
      Reminder(title: 'Lavar el auto', dueAt: tomorrow),
    );
    expect(scheduler.scheduled[r.id], tomorrow);

    await repo.setDone(r.id!, true);
    expect(scheduler.scheduled, isEmpty);

    await repo.setDone(r.id!, false);
    expect(scheduler.scheduled[r.id], tomorrow);

    await repo.delete(r.id!);
    expect(scheduler.scheduled, isEmpty);
  });

  test('no programa recordatorios con fecha pasada', () async {
    await repo.save(
      Reminder(
        title: 'Ayer',
        dueAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );
    expect(scheduler.scheduled, isEmpty);
  });

  test('el botón Hecho marca el recordatorio', () async {
    final r = await repo.save(Reminder(title: 'Pagar la luz', dueAt: tomorrow));
    expect(await actions.handle(r.id!, ReminderActions.doneActionId), isTrue);
    expect((await repo.getById(r.id!))!.done, isTrue);
    expect(scheduler.scheduled, isEmpty);
  });

  test('posponer mueve la hora y reprograma el aviso', () async {
    final r = await repo.save(Reminder(title: 'Llamar', dueAt: tomorrow));
    final now = DateTime(2030, 1, 1, 10);
    final expected = {
      'snooze_15m': DateTime(2030, 1, 1, 10, 15),
      'snooze_1h': DateTime(2030, 1, 1, 11),
      'snooze_tomorrow': DateTime(2030, 1, 2, 10),
    };
    for (final entry in expected.entries) {
      final option = snoozeOptionById(entry.key)!;
      final moved = await actions.snooze(r.id!, option, now: now);
      expect(moved!.dueAt, entry.value, reason: option.label);
      expect(scheduler.scheduled[r.id], entry.value);
    }
  });

  test('ignora botones desconocidos', () async {
    final r = await repo.save(Reminder(title: 'X', dueAt: tomorrow));
    expect(await actions.handle(r.id!, null), isFalse);
    expect(await actions.handle(r.id!, 'otro'), isFalse);
  });

  test(
    'la notificación tiene Hecho y como máximo dos opciones de posponer',
    () {
      expect(
        snoozeOptions.where((o) => o.showInNotification).length,
        lessThanOrEqualTo(2),
      );
    },
  );
}
