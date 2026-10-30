import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/theme.dart';
import 'data/reminder_repository.dart';
import 'features/home/home_shell.dart';
import 'features/update/update_prompt.dart';

class RecordameApp extends StatelessWidget {
  const RecordameApp({super.key, required this.reminders});

  final ReminderRepository reminders;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      reminders: reminders,
      child: MaterialApp(
        title: 'Recordame',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        locale: const Locale('es', 'AR'),
        supportedLocales: const [Locale('es', 'AR'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const UpdatePrompt(child: HomeShell()),
      ),
    );
  }
}
