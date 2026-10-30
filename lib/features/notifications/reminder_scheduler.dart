import '../../data/reminder.dart';

/// Programa los avisos de los recordatorios.
abstract class ReminderScheduler {
  Future<void> schedule(Reminder reminder);

  Future<void> cancel(int reminderId);

  /// Borra todos los avisos y vuelve a programar los pendientes.
  Future<void> rescheduleAll(List<Reminder> reminders);
}

/// No programa nada. Se usa en la vista web y en las pruebas.
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<void> schedule(Reminder reminder) async {}

  @override
  Future<void> cancel(int reminderId) async {}

  @override
  Future<void> rescheduleAll(List<Reminder> reminders) async {}
}
