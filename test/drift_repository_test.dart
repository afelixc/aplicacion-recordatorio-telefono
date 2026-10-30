import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/drift/database.dart';
import 'package:recordame/data/drift/drift_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';
import 'package:recordame/data/reminder.dart';

void main() {
  late AppDatabase db;
  late DriftReminderRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftReminderRepository(db);
  });
  tearDown(() => db.close());

  test('guarda, ordena por fecha, edita, marca como hecho y borra', () async {
    final a = await repo.save(
      Reminder(title: 'B', dueAt: DateTime(2026, 11, 6, 9)),
    );
    final b = await repo.save(
      Reminder(title: 'A', dueAt: DateTime(2026, 11, 3, 16)),
    );

    var all = await repo.watchAll().first;
    expect(all.map((r) => r.title), ['A', 'B']);

    await repo.save(a.copyWith(title: 'Lavar el auto'));
    expect((await repo.getById(a.id!))!.title, 'Lavar el auto');

    await repo.setDone(b.id!, true);
    final done = (await repo.getById(b.id!))!;
    expect(done.done, isTrue);
    expect(done.completedAt, isNotNull);

    await repo.setDone(b.id!, false);
    expect((await repo.getById(b.id!))!.completedAt, isNull);

    await repo.delete(a.id!);
    all = await repo.watchAll().first;
    expect(all.map((r) => r.title), ['A']);
  });

  test('guarda la repetición', () async {
    final r = await repo.save(
      Reminder(
        title: 'Gimnasio',
        dueAt: DateTime(2026, 11, 2, 19),
        recurrence: Recurrence.weekly({DateTime.monday, DateTime.thursday}),
        snoozedUntil: DateTime(2026, 11, 2, 20),
      ),
    );
    final back = (await repo.getById(r.id!))!;
    expect(back.recurrence.kind, RepeatKind.weekly);
    expect(back.recurrence.weekdays, {DateTime.monday, DateTime.thursday});
    expect(back.snoozedUntil, DateTime(2026, 11, 2, 20));
  });
}
