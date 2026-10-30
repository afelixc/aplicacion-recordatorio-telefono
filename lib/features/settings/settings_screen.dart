import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/settings.dart';
import 'ai_section.dart';
import 'notifications_section.dart';

/// Configuración: modo de uso, IA, idioma, notificaciones.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final notifications = scope.notifications;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SettingsCard(
            title: 'Modo de uso',
            children: [
              SegmentedButton<UsageMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: UsageMode.free,
                    label: Text('Gratis (manual)'),
                    icon: Icon(Icons.edit_note),
                  ),
                  ButtonSegment(
                    value: UsageMode.ai,
                    label: Text('Con IA'),
                    icon: Icon(Icons.auto_awesome),
                  ),
                ],
                selected: {settings.mode},
                onSelectionChanged: (s) => settings.setMode(s.first),
              ),
              Text(
                settings.mode == UsageMode.free
                    ? 'Cargás qué, día y hora con un formulario. No usa internet ni gasta saldo.'
                    : 'Escribís o hablás normal ("recordame el viernes a las 9 lavar el auto") y la IA arma el recordatorio. Usa tu propia clave y tu saldo.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          if (settings.mode == UsageMode.ai) ...[
            const SizedBox(height: 12),
            AiSection(settings: settings),
          ],
          const SizedBox(height: 12),
          SettingsCard(
            title: 'Idioma',
            children: [
              DropdownButtonFormField<String>(
                initialValue: settings.language,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.language),
                ),
                items: [
                  for (final (code, label) in appLanguages)
                    DropdownMenuItem(value: code, child: Text(label)),
                ],
                onChanged: (v) {
                  if (v != null) settings.setLanguage(v);
                },
              ),
              Text(
                'Idioma en el que te entiende y te contesta la IA, y del dictado por voz.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (notifications != null)
            NotificationsSection(service: notifications)
          else
            const SettingsCard(
              title: 'Notificaciones',
              children: [
                Text('Las notificaciones solo funcionan en el teléfono.'),
              ],
            ),
          const SizedBox(height: 12),
          const SettingsCard(
            title: 'Próximamente',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_available),
                title: Text('Sincronizar con Google Calendar'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.cloud_upload_outlined),
                title: Text('Copia de seguridad en Google Drive'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recuadro de una sección de Configuración.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            ...children,
          ],
        ),
      ),
    );
  }
}
