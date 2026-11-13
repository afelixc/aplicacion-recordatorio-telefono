import 'package:flutter/material.dart';

import '../../core/sheets.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../data/reminder.dart';
import 'reminder_form.dart';

/// Abre el formulario en una hoja desde abajo para crear o editar un recordatorio.
Future<void> showReminderEditor(
  BuildContext context, {
  Reminder? reminder,
  DateTime? initialDay,
  String initialTitle = '',
}) {
  final repo = AppScope.of(context).reminders;
  final messenger = ScaffoldMessenger.of(context);
  Reminder? initial = reminder;
  if (initial == null && (initialDay != null || initialTitle.isNotEmpty)) {
    final day = initialDay ?? DateTime.now().add(const Duration(days: 1));
    initial = Reminder(
      title: initialTitle,
      dueAt: DateTime(day.year, day.month, day.day, 9),
    );
  }
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            reminder == null ? 'Nuevo recordatorio' : 'Editar recordatorio',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ReminderForm(
            initial: initial,
            submitLabel: 'Guardar',
            onCancel: () => Navigator.pop(context),
            onSubmit: (r) async {
              final navigator = Navigator.of(context);
              await repo.save(r);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Guardado: ${describeSchedule(r)}')),
              );
            },
          ),
        ],
      ),
    ),
  );
}
