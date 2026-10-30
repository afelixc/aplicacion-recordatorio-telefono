import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/formatting.dart';
import 'data/drift/database.dart';
import 'data/drift/drift_reminder_repository.dart';
import 'data/memory_reminder_repository.dart';
import 'data/reminder.dart';
import 'data/scheduling_reminder_repository.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/reminder_actions.dart';
import 'features/notifications/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(Fmt.locale);

  // La vista previa web solo sirve para mirar el diseño: datos de ejemplo en
  // memoria y sin notificaciones.
  if (kIsWeb) {
    runApp(
      RecordameApp(
        reminders: SchedulingReminderRepository(
          MemoryReminderRepository(_sampleReminders()),
          const NoopReminderScheduler(),
        ),
      ),
    );
    return;
  }

  final notifications = NotificationService.instance;
  await notifications.init();
  final reminders = SchedulingReminderRepository(
    DriftReminderRepository(AppDatabase()),
    notifications,
  );
  notifications.foregroundActions = ReminderActions(reminders);

  runApp(
    RecordameApp(
      reminders: reminders,
      openedReminders: notifications.openedReminders,
      launchReminderId: notifications.launchReminderId,
    ),
  );

  // Después de mostrar la app: pedir permiso y dejar todos los avisos al día.
  await notifications.requestPermission();
  await reminders.resync();
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
