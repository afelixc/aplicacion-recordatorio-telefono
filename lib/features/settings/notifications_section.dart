import 'package:flutter/material.dart';

import '../notifications/notification_service.dart';

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
                  onPressed: () => _run(
                    service.openBatterySettings,
                    'Elegí "Permitir" o "Sin restricciones".',
                  ),
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
