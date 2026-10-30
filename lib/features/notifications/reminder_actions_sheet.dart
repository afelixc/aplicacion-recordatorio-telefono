import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import 'reminder_actions.dart';
import 'snooze_options.dart';

/// Se abre al tocar una notificación: "Hecho" y todas las opciones de posponer.
Future<void> showReminderActionsSheet(
  BuildContext context,
  int reminderId,
) async {
  final repo = AppScope.of(context).reminders;
  final reminder = await repo.getById(reminderId);
  if (reminder == null || !context.mounted) return;
  final actions = ReminderActions(repo);
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reminder.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(Fmt.when(reminder.dueAt)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Hecho'),
              onPressed: () async {
                Navigator.pop(context);
                await actions.markDone(reminderId);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Marcado como hecho')),
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Posponer', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in snoozeOptions)
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final r = await actions.snooze(reminderId, option);
                      if (r != null) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Pospuesto para ${Fmt.when(r.dueAt)}',
                            ),
                          ),
                        );
                      }
                    },
                    child: Text(option.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
