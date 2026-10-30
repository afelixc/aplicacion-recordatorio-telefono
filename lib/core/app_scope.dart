import 'package:flutter/widgets.dart';

import '../data/reminder_repository.dart';
import '../features/ai/ai_provider.dart';
import '../features/notifications/notification_service.dart';
import 'settings.dart';

/// Pone los servicios de la app al alcance de todas las pantallas.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.reminders,
    required this.settings,
    this.notifications,
    this.aiProviderOverride,
    required super.child,
  });

  final ReminderRepository reminders;
  final AppSettings settings;

  /// Null en la vista web y en las pruebas, donde no hay notificaciones.
  final NotificationService? notifications;

  /// Solo para las pruebas: reemplaza al proveedor de IA real.
  final AiProvider? aiProviderOverride;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      reminders != oldWidget.reminders ||
      settings != oldWidget.settings ||
      notifications != oldWidget.notifications;
}
