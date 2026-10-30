import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

@DataClassName('ReminderRow')
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get dueAt => dateTime()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Reservado para la sincronización con Google Calendar (segunda etapa).
  TextColumn get calendarEventId => text().nullable()();

  // Repetición (versión 2 de la base).
  TextColumn get repeatKind => text().withDefault(const Constant('none'))();
  IntColumn get repeatWeekdays => integer().withDefault(const Constant(0))();
  TextColumn get repeatDates => text().nullable()();
  DateTimeColumn get lastDoneAt => dateTime().nullable()();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
}

@DriftDatabase(tables: [Reminders])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'recordame',
              // La app y los botones de la notificación (que corren aparte)
              // comparten la misma base.
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  /// Subir este número y agregar los pasos en [migration] cuando cambien las tablas.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(reminders, reminders.repeatKind);
        await m.addColumn(reminders, reminders.repeatWeekdays);
        await m.addColumn(reminders, reminders.repeatDates);
        await m.addColumn(reminders, reminders.lastDoneAt);
        await m.addColumn(reminders, reminders.snoozedUntil);
      }
    },
  );
}
