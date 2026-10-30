import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:recordame/data/drift/database.dart';
import 'package:recordame/data/drift/drift_reminder_repository.dart';
import 'package:recordame/data/recurrence.dart';

void main() {
  test('los recordatorios de la versión 1 de la base no se pierden', () async {
    // Base como la dejaba la versión 1.0.5 de la app.
    final executor = NativeDatabase.memory(
      setup: (db) {
        db.execute('''
          CREATE TABLE reminders (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            due_at INTEGER NOT NULL,
            done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0, 1)),
            completed_at INTEGER NULL,
            created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
            updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
            calendar_event_id TEXT NULL
          );
        ''');
        final due = DateTime(2026, 11, 6, 9).millisecondsSinceEpoch ~/ 1000;
        db.execute(
          "INSERT INTO reminders (title, due_at) VALUES ('Lavar el auto', $due);",
        );
        db.execute('PRAGMA user_version = 1;');
      },
    );
    final db = AppDatabase(executor);
    final all = await DriftReminderRepository(db).watchAll().first;
    expect(all.single.title, 'Lavar el auto');
    expect(all.single.dueAt, DateTime(2026, 11, 6, 9));
    expect(all.single.recurrence.kind, RepeatKind.none);
    await db.close();
  });
}
