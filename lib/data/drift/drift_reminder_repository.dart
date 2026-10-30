import 'package:drift/drift.dart';

import '../reminder.dart';
import '../reminder_repository.dart';
import 'database.dart';

/// Guarda los recordatorios en la base SQLite del teléfono.
class DriftReminderRepository implements ReminderRepository {
  DriftReminderRepository(this._db);

  final AppDatabase _db;

  static Reminder _fromRow(ReminderRow r) => Reminder(
    id: r.id,
    title: r.title,
    dueAt: r.dueAt,
    done: r.done,
    completedAt: r.completedAt,
    calendarEventId: r.calendarEventId,
  );

  @override
  Stream<List<Reminder>> watchAll() {
    final query = _db.select(_db.reminders)
      ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  @override
  Future<Reminder?> getById(int id) async {
    final query = _db.select(_db.reminders)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<Reminder> save(Reminder reminder) async {
    final companion = RemindersCompanion(
      title: Value(reminder.title),
      dueAt: Value(reminder.dueAt),
      done: Value(reminder.done),
      completedAt: Value(reminder.completedAt),
      updatedAt: Value(DateTime.now()),
    );
    if (reminder.id == null) {
      final id = await _db.into(_db.reminders).insert(companion);
      return reminder.copyWith(id: id);
    }
    await (_db.update(
      _db.reminders,
    )..where((t) => t.id.equals(reminder.id!))).write(companion);
    return reminder;
  }

  @override
  Future<void> setDone(int id, bool done) async {
    await (_db.update(_db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        done: Value(done),
        completedAt: Value(done ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.reminders)..where((t) => t.id.equals(id))).go();
  }
}
