import 'reminder.dart';

/// Acceso a los recordatorios guardados.
///
/// La app solo habla con esta interfaz, así se puede cambiar dónde se guardan
/// (base local, memoria para pruebas, o sumar sincronización más adelante)
/// sin tocar las pantallas.
abstract class ReminderRepository {
  /// Todos los recordatorios ordenados por fecha; emite de nuevo con cada cambio.
  Stream<List<Reminder>> watchAll();

  Future<Reminder?> getById(int id);

  /// Crea el recordatorio si no tiene id, o lo actualiza. Devuelve el guardado.
  Future<Reminder> save(Reminder reminder);

  Future<void> setDone(int id, bool done);

  Future<void> delete(int id);
}
