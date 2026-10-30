/// Una opción de "Posponer".
class SnoozeOption {
  const SnoozeOption({
    required this.id,
    required this.label,
    required this.apply,
    this.showInNotification = false,
  });

  /// Identificador fijo (se usa en los botones de la notificación).
  final String id;
  final String label;

  /// Calcula la nueva fecha a partir de ahora.
  final DateTime Function(DateTime now) apply;

  /// Si aparece como botón en la notificación. Android muestra como máximo
  /// tres botones y uno es "Hecho", así que solo entran dos. Las demás opciones
  /// aparecen al tocar la notificación.
  final bool showInNotification;
}

/// Opciones de "Posponer". Para sumar una, agregala a esta lista.
final List<SnoozeOption> snoozeOptions = [
  SnoozeOption(
    id: 'snooze_15m',
    label: '15 min',
    apply: (now) => now.add(const Duration(minutes: 15)),
    showInNotification: true,
  ),
  SnoozeOption(
    id: 'snooze_1h',
    label: '1 hora',
    apply: (now) => now.add(const Duration(hours: 1)),
    showInNotification: true,
  ),
  SnoozeOption(
    id: 'snooze_tomorrow',
    label: 'Mañana',
    apply: (now) => now.add(const Duration(days: 1)),
  ),
];

SnoozeOption? snoozeOptionById(String? id) =>
    snoozeOptions.where((o) => o.id == id).firstOrNull;
