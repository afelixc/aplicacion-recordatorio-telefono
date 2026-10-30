import 'package:flutter/widgets.dart';

import '../data/reminder_repository.dart';

/// Pone los servicios de la app al alcance de todas las pantallas.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.reminders, required super.child});

  final ReminderRepository reminders;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      reminders != oldWidget.reminders;
}
