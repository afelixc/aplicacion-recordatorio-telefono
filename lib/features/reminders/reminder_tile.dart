import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../data/reminder.dart';
import 'reminder_editor.dart';

/// Un recordatorio en una lista: marcar como hecho, editar y borrar.
class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.reminder});

  final Reminder reminder;

  Future<void> _delete(BuildContext context) async {
    final repo = AppScope.of(context).reminders;
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(reminder.id!);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Borrado: ${reminder.title}'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () => repo.save(reminder),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = AppScope.of(context).reminders;
    final overdue = !reminder.done && reminder.dueAt.isBefore(DateTime.now());
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        leading: Checkbox(
          shape: const CircleBorder(),
          value: reminder.done,
          onChanged: (v) => repo.setDone(reminder.id!, v ?? false),
        ),
        title: Text(
          reminder.title,
          style: reminder.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          overdue
              ? '${Fmt.when(reminder.dueAt)} · vencido'
              : Fmt.when(reminder.dueAt),
          style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
        ),
        onTap: () => showReminderEditor(context, reminder: reminder),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showReminderEditor(context, reminder: reminder),
            ),
            IconButton(
              tooltip: 'Borrar',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context),
            ),
          ],
        ),
      ),
    );
  }
}
