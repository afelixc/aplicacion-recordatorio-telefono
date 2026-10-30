import '../../data/reminder.dart';
import '../../data/reminder_repository.dart';
import 'snooze_options.dart';

/// Lo que se puede hacer desde una notificación: marcar como hecho o posponer.
/// Se usa tanto desde los botones de la notificación como desde la app.
class ReminderActions {
  ReminderActions(this._repo);

  final ReminderRepository _repo;

  static const doneActionId = 'done';

  Future<void> markDone(int id) => _repo.setDone(id, true);

  /// Mueve el recordatorio a la nueva hora (y con eso reprograma el aviso).
  Future<Reminder?> snooze(int id, SnoozeOption option, {DateTime? now}) async {
    final reminder = await _repo.getById(id);
    if (reminder == null) return null;
    return _repo.save(
      reminder.copyWith(dueAt: option.apply(now ?? DateTime.now())),
    );
  }

  /// Ejecuta la acción de un botón de la notificación. Devuelve false si el
  /// botón no es conocido.
  Future<bool> handle(int id, String? actionId) async {
    if (actionId == doneActionId) {
      await markDone(id);
      return true;
    }
    final option = snoozeOptionById(actionId);
    if (option == null) return false;
    await snooze(id, option);
    return true;
  }
}
