import '../features/notifications/reminder_scheduler.dart';
import 'reminder.dart';
import 'reminder_repository.dart';

/// Envuelve otro repositorio y mantiene los avisos al día: cada vez que se
/// guarda, se marca como hecho o se borra un recordatorio, programa o cancela
/// su notificación.
class SchedulingReminderRepository implements ReminderRepository {
  SchedulingReminderRepository(this._inner, this._scheduler);

  final ReminderRepository _inner;
  final ReminderScheduler _scheduler;

  @override
  Stream<List<Reminder>> watchAll() => _inner.watchAll();

  @override
  Future<Reminder?> getById(int id) => _inner.getById(id);

  @override
  Future<Reminder> save(Reminder reminder) async {
    final saved = await _inner.save(reminder);
    await _scheduler.schedule(saved);
    return saved;
  }

  @override
  Future<void> setDone(int id, bool done) async {
    await _inner.setDone(id, done);
    final reminder = await _inner.getById(id);
    if (reminder != null) await _scheduler.schedule(reminder);
  }

  @override
  Future<void> delete(int id) async {
    await _scheduler.cancel(id);
    await _inner.delete(id);
  }

  /// Vuelve a programar todos los pendientes (por ejemplo, al abrir la app).
  Future<void> resync() async =>
      _scheduler.rescheduleAll(await _inner.watchAll().first);
}
