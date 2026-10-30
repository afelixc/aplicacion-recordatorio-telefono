import '../../data/reminder_repository.dart';
import 'snooze_options.dart';

/// Lo que se puede hacer desde una notificación: marcar como hecho o posponer.
/// Se usa tanto desde los botones de la notificación como desde la app.
class ReminderActions {
  ReminderActions(this._repo);

  final ReminderRepository _repo;

  static const doneActionId = 'done';

  /// En uno que no se repite, lo da por terminado. En uno que se repite,
  /// solo da por hecha esta vez: sigue avisando las próximas.
  Future<void> markDone(int id, {DateTime? now}) async {
    final reminder = await _repo.getById(id);
    if (reminder == null) return;
    if (reminder.repeats) {
      await _repo.save(
        reminder.copyWith(
          lastDoneAt: now ?? DateTime.now(),
          clearSnoozedUntil: true,
        ),
      );
    } else {
      await _repo.setDone(id, true);
    }
  }

  /// Vuelve a avisar más tarde y devuelve la nueva hora del aviso.
  /// En uno que no se repite mueve su fecha; en uno que se repite agrega un
  /// aviso extra sin tocar las próximas repeticiones.
  Future<DateTime?> snooze(int id, SnoozeOption option, {DateTime? now}) async {
    final reminder = await _repo.getById(id);
    if (reminder == null) return null;
    final at = option.apply(now ?? DateTime.now());
    await _repo.save(
      reminder.repeats
          ? reminder.copyWith(snoozedUntil: at)
          : reminder.copyWith(dueAt: at),
    );
    return at;
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
