import 'package:flutter/widgets.dart';

import '../data/reminder_repository.dart';
import '../features/notifications/notification_service.dart';

/// Pone los servicios de la app al alcance de todas las pantallas.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.reminders,
    this.notifications,
    required super.child,
  });

  final ReminderRepository reminders;

  /// Null en la vista web y en las pruebas, donde no hay notificaciones.
  final NotificationService? notifications;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      reminders != oldWidget.reminders ||
      notifications != oldWidget.notifications;
}
