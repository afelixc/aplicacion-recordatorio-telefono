import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/formatting.dart';
import 'core/settings.dart';
import 'data/drift/database.dart';
import 'data/drift/drift_reminder_repository.dart';
import 'data/drift/drift_usage_repository.dart';
import 'data/memory_reminder_repository.dart';
import 'data/reminder.dart';
import 'data/scheduling_reminder_repository.dart';
import 'features/ai/ai_providers.dart';
import 'features/backup/backup_service.dart';
import 'features/calendar_sync/calendar_sync.dart';
import 'features/calendar_sync/device_calendar.dart';
import 'features/notifications/notification_service.dart';
import 'features/notifications/reminder_actions.dart';
import 'features/notifications/reminder_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(Fmt.locale);

  // La vista previa web solo sirve para mirar el diseño: datos de ejemplo en
  // memoria y sin notificaciones.
  final providerIds = aiProviders.map((p) => p.id);

  if (kIsWeb) {
    final settings = AppSettings(MemorySettingsStore(), MemoryKeyStore());
    await settings.load(providerIds);
    runApp(
      RecordameApp(
        settings: settings,
        reminders: SchedulingReminderRepository(
          MemoryReminderRepository(_sampleReminders()),
          const NoopReminderScheduler(),
        ),
      ),
    );
    return;
  }

  final settings = AppSettings(PrefsSettingsStore(), SecureKeyStore());
  await settings.load(providerIds);

  final notifications = NotificationService.instance;
  await notifications.init();
  final db = AppDatabase();
  final calendar = CalendarSync(
    calendar: AndroidDeviceCalendar(),
    settings: settings,
  );
  final reminders = SchedulingReminderRepository(
    CalendarSyncRepository(DriftReminderRepository(db), calendar),
    notifications,
  );
  notifications.foregroundActions = ReminderActions(reminders);
  final usage = DriftUsageRepository(db);
  final backup = BackupService(
    reminders: reminders,
    usage: usage,
    settings: settings,
    files: AndroidBackupFiles(),
  );

  runApp(
    RecordameApp(
      reminders: reminders,
      settings: settings,
      usage: usage,
      backup: backup,
      calendar: calendar,
      notifications: notifications,
      openedReminders: notifications.openedReminders,
      launchReminderId: notifications.launchReminderId,
    ),
  );

  // Después de mostrar la app: pedir permiso y dejar todos los avisos al día.
  await notifications.requestPermission();
  await reminders.resync();

  // Al abrir o volver a la app: traer lo nuevo del calendario (si está
  // prendido) y la copia automática una vez por día.
  Future<void> refresh() async {
    try {
      await calendar.autoImport(reminders);
    } catch (_) {}
    await backup.autoBackup();
  }

  await refresh();
  _lifecycle = AppLifecycleListener(onResume: refresh);
}

// ignore: unused_element
AppLifecycleListener? _lifecycle;

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
