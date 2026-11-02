import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/palette.dart';
import 'core/settings.dart';
import 'features/ai/ai_provider.dart';
import 'features/backup/backup_service.dart';
import 'features/calendar_sync/calendar_sync.dart';
import 'features/gmail/gmail_sync.dart';
import 'core/theme.dart';
import 'data/reminder_repository.dart';
import 'data/usage.dart';
import 'features/home/home_shell.dart';
import 'features/notifications/notification_service.dart';
import 'features/update/update_prompt.dart';

class RecordameApp extends StatelessWidget {
  const RecordameApp({
    super.key,
    required this.reminders,
    required this.settings,
    this.usage,
    this.notifications,
    this.aiProviderOverride,
    this.backup,
    this.calendar,
    this.gmail,
    this.openedReminders = const Stream.empty(),
    this.launchReminderId,
  });

  final ReminderRepository reminders;
  final AppSettings settings;

  /// Si es null se usa un registro en memoria (vista web y pruebas).
  final UsageRepository? usage;
  final NotificationService? notifications;
  final AiProvider? aiProviderOverride;
  final BackupService? backup;
  final CalendarSync? calendar;
  final GmailSync? gmail;

  /// Recordatorios cuya notificación se tocó con la app abierta.
  final Stream<int> openedReminders;

  /// Recordatorio cuya notificación abrió la app.
  final int? launchReminderId;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      reminders: reminders,
      settings: settings,
      usage: usage ?? _memoryUsage,
      notifications: notifications,
      aiProviderOverride: aiProviderOverride,
      backup: backup,
      calendar: calendar,
      gmail: gmail,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'Recordame',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(settings.dayColors),
          darkTheme: AppTheme.dark(settings.nightColors),
          themeMode: switch (settings.dayNight) {
            DayNight.auto => ThemeMode.system,
            DayNight.day => ThemeMode.light,
            DayNight.night => ThemeMode.dark,
          },
          locale: const Locale('es', 'AR'),
          supportedLocales: const [Locale('es', 'AR'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: UpdatePrompt(
            child: HomeShell(
              openedReminders: openedReminders,
              launchReminderId: launchReminderId,
            ),
          ),
        ),
      ),
    );
  }
}

final _memoryUsage = MemoryUsageRepository();
