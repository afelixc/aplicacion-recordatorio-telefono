import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/drift/database.dart';
import 'data/drift/drift_reminder_repository.dart';
import 'data/memory_reminder_repository.dart';
import 'data/reminder.dart';
import 'data/reminder_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR');

  // En el teléfono se usa la base de datos local. La vista previa web solo
  // sirve para mirar el diseño, así que usa datos de ejemplo en memoria.
  final ReminderRepository reminders = kIsWeb
      ? MemoryReminderRepository(_sampleReminders())
      : DriftReminderRepository(AppDatabase());

  runApp(RecordameApp(reminders: reminders));
}

List<Reminder> _sampleReminders() {
  final now = DateTime.now();
  DateTime at(int days, int hour, [int minute = 0]) =>
      DateTime(now.year, now.month, now.day + days, hour, minute);
  return [
    Reminder(title: 'Pagar la luz', dueAt: at(0, 18)),
    Reminder(title: 'Turno con el dentista', dueAt: at(4, 16, 30)),
    Reminder(title: 'Lavar el auto', dueAt: at(7, 9)),
    Reminder(title: 'Cumpleaños de mamá', dueAt: at(13, 10)),
    Reminder(title: 'Llamar al contador', dueAt: at(-2, 11), done: true),
  ];
}
