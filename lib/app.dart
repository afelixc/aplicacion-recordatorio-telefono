import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/settings.dart';
import 'features/ai/ai_provider.dart';
import 'core/theme.dart';
import 'data/reminder_repository.dart';
import 'features/home/home_shell.dart';
import 'features/notifications/notification_service.dart';
import 'features/update/update_prompt.dart';

class RecordameApp extends StatelessWidget {
  const RecordameApp({
    super.key,
    required this.reminders,
    required this.settings,
    this.notifications,
    this.aiProviderOverride,
    this.openedReminders = const Stream.empty(),
    this.launchReminderId,
  });

  final ReminderRepository reminders;
  final AppSettings settings;
  final NotificationService? notifications;
  final AiProvider? aiProviderOverride;

  /// Recordatorios cuya notificación se tocó con la app abierta.
  final Stream<int> openedReminders;

  /// Recordatorio cuya notificación abrió la app.
  final int? launchReminderId;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      reminders: reminders,
      settings: settings,
      notifications: notifications,
      aiProviderOverride: aiProviderOverride,
      child: MaterialApp(
        title: 'Recordame',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
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
    );
  }
}
