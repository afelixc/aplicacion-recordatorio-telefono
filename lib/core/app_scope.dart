import 'package:flutter/widgets.dart';

import '../data/reminder_repository.dart';
import '../data/usage.dart';
import '../features/ai/ai_provider.dart';
import '../features/backup/backup_service.dart';
import '../features/calendar_sync/calendar_sync.dart';
import '../features/gmail/gmail_sync.dart';
import '../features/notifications/notification_service.dart';
import 'settings.dart';

/// Pone los servicios de la app al alcance de todas las pantallas.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.reminders,
    required this.settings,
    required this.usage,
    this.notifications,
    this.aiProviderOverride,
    this.backup,
    this.calendar,
    this.gmail,
    required super.child,
  });

  final ReminderRepository reminders;
  final AppSettings settings;

  /// Registro de consultas a la IA.
  final UsageRepository usage;

  /// Null en la vista web y en las pruebas, donde no hay notificaciones.
  final NotificationService? notifications;

  /// Copia de seguridad (null en la vista web).
  final BackupService? backup;

  /// Google Calendar del teléfono (null en la vista web).
  final CalendarSync? calendar;

  /// Gmail en la compu (null en la vista web).
  final GmailSync? gmail;

  /// Solo para las pruebas: reemplaza al proveedor de IA real.
  final AiProvider? aiProviderOverride;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      reminders != oldWidget.reminders ||
      settings != oldWidget.settings ||
      usage != oldWidget.usage ||
      notifications != oldWidget.notifications ||
      backup != oldWidget.backup ||
      calendar != oldWidget.calendar ||
      gmail != oldWidget.gmail;
}
