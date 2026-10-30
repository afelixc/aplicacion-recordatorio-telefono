import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/home/home_shell.dart';

class RecordameApp extends StatelessWidget {
  const RecordameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recordame',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
