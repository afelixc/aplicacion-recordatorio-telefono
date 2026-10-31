import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../data/reminder.dart';
import 'reminder_editor.dart';

/// Un recordatorio en una lista: marcar como hecho, editar y borrar.
class ReminderTile extends StatelessWidget {
  const ReminderTile({
    super.key,
    required this.reminder,
    this.highlightDone = false,
  });

  final Reminder reminder;

  /// Pinta los hechos de amarillo clarito para distinguirlos de los pendientes.
  final bool highlightDone;

  Future<void> _delete(BuildContext context) async {
    final repo = AppScope.of(context).reminders;
    final messenger = ScaffoldMessenger.of(context);
    await repo.delete(reminder.id!);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Borrado: ${reminder.title}'),
        // 5 segundos para deshacer; después se va solo y queda borrado.
        duration: const Duration(seconds: 5),
        persist: false,
        showCloseIcon: true,
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
    final overdue =
        !reminder.done &&
        !reminder.repeats &&
        reminder.dueAt.isBefore(DateTime.now());
    final next = reminder.repeats ? reminder.nextOccurrence() : null;
    final tinted = highlightDone && reminder.done;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tinted ? const Color(0xFFFFF4D6) : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: tinted
              ? const Color(0xFFE8C77A)
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        leading: Checkbox(
          // En uno que se repite, tildarlo corta la repetición.
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                describeSchedule(reminder),
                if (overdue) 'vencido',
                if (reminder.repeats && !reminder.done)
                  next == null
                      ? 'sin más fechas'
                      : 'próximo: ${Fmt.when(next)}',
              ].join(reminder.repeats ? '\n' : ' · '),
              style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
            ),
            if (overdue)
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.update, size: 18),
                label: const Text('Reprogramar'),
                onPressed: () =>
                    showReminderEditor(context, reminder: reminder),
              ),
          ],
        ),
        isThreeLine: overdue || (reminder.repeats && !reminder.done),
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
