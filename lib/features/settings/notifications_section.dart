import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/reminder_repository.dart';
import '../../data/scheduling_reminder_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/notification_sound.dart';
import 'battery_help.dart';
import 'priorities_page.dart';

/// Estado de las notificaciones, accesos a los ajustes de Android y avisos de prueba.
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key, required this.service});

  final NotificationService service;

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection>
    with WidgetsBindingObserver {
  late Future<NotificationStatus> _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = widget.service.status();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver de los ajustes de Android, actualizar el estado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => setState(() => _status = widget.service.status());

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = widget.service;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<NotificationStatus>(
          future: _status,
          builder: (context, snapshot) {
            final s = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Notificaciones', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('Sonido del aviso'),
                    subtitle: Text(service.soundName),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await showSoundPicker(context, service);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 16),
                PrioritiesSection(service: service),
                const SizedBox(height: 16),
                if (s == null)
                  const LinearProgressIndicator()
                else ...[
                  _StatusRow(
                    ok: s.enabled,
                    okText: 'Notificaciones permitidas',
                    badText: 'Notificaciones bloqueadas',
                    actionLabel: 'Permitir',
                    onAction: () async {
                      final granted = await service.requestPermission();
                      if (!granted) await service.openNotificationSettings();
                      _refresh();
                    },
                  ),
                  _StatusRow(
                    ok: s.exactAlarms,
                    okText: 'Avisos a la hora exacta',
                    badText: 'Avisos a la hora exacta no permitidos',
                    actionLabel: 'Permitir',
                    onAction: () async {
                      await service.requestExactAlarms();
                      _refresh();
                    },
                  ),
                  Text(
                    'Avisos programados: ${s.pending} · Zona horaria: ${s.timeZone}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (s.lastError != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      'Último error: ${s.lastError}',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.battery_saver_outlined),
                  label: const Text('Evitar que el teléfono cierre la app'),
                  onPressed: () => showBatteryHelp(context),
                ),
                const SizedBox(height: 16),
                Text('Probar', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () =>
                            _run(service.showTest, 'Aviso de prueba enviado'),
                        child: const Text('Aviso ahora'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _run(
                          () =>
                              service.scheduleTest(const Duration(minutes: 1)),
                          'Te llega un aviso en 1 minuto. Podés cerrar la app.',
                        ),
                        child: const Text('Aviso en 1 minuto'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.ok,
    required this.okText,
    required this.badText,
    required this.actionLabel,
    required this.onAction,
  });

  final bool ok;
  final String okText;
  final String badText;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error,
            color: ok ? Colors.green : scheme.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(ok ? okText : badText)),
          if (!ok) TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// Lista de sonidos: los de Recordame y "Elegir otro del teléfono".
/// Tocar el ▶ lo hace sonar; tocar el nombre lo elige.
Future<void> showSoundPicker(
  BuildContext context,
  NotificationService service,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _SoundSheet(
      service: service,
      reminders: AppScope.of(context).reminders,
    ),
  ).whenComplete(SoundPicker.stop);
}

class _SoundSheet extends StatefulWidget {
  const _SoundSheet({required this.service, required this.reminders});

  final NotificationService service;
  final ReminderRepository reminders;

  @override
  State<_SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<_SoundSheet> {
  bool _saving = false;

  Future<void> _choose(SoundChoice choice) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await widget.service.setSound(choice);
      // Los avisos ya programados pasan al sonido nuevo.
      final repo = widget.reminders;
      if (repo is SchedulingReminderRepository) await repo.resync();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Listo: "${choice.name}". Probalo con "Aviso ahora".'),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('No se pudo: $e')));
    }
  }

  Future<void> _fromPhone() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await SoundPicker.pickFromPhone(widget.service.soundUri);
      if (picked != null) await _choose(picked);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Este teléfono no deja elegir sonidos desde otra app.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.service.soundUri;
    final custom =
        current != null && !builtInSounds.any((s) => s.uri == current);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sonido de los recordatorios',
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Tocá ▶ para escucharlo y el nombre para elegirlo.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            for (final s in builtInSounds)
              ListTile(
                leading: IconButton(
                  tooltip: 'Escuchar ${s.name}',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => SoundPicker.play(s.uri),
                ),
                title: Text(s.name),
                trailing: s.uri == current
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : null,
                onTap: _saving ? null : () => _choose(s),
              ),
            if (custom)
              ListTile(
                leading: IconButton(
                  tooltip: 'Escuchar',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: () => SoundPicker.play(current),
                ),
                title: Text(widget.service.soundName),
                subtitle: const Text('Del teléfono'),
                trailing: Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                ),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('Elegir otro sonido del teléfono…'),
              subtitle: const Text('Tonos, alarmas y notificaciones'),
              onTap: _saving ? null : _fromPhone,
            ),
          ],
        ),
      ),
    );
  }
}
