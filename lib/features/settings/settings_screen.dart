import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../ai/ai_providers.dart';
import '../help/modes_help.dart';
import 'ai_section.dart';
import 'backup_section.dart';
import 'notifications_section.dart';
import 'usage_section.dart';

/// Configuración: un menú corto; cada opción se abre en su propia pantalla.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final provider = providerById(settings.providerId);
        final model = settings.modelFor(provider.id) ?? provider.defaultModel;
        final suggested = {
          for (final (id, d) in provider.suggestedModels)
            id: d.split(':').first,
        };
        final language = appLanguages
            .firstWhere(
              (l) => l.$1 == settings.language,
              orElse: () => appLanguages.first,
            )
            .$2;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            _MenuItem(
              icon: Icons.tune,
              title: 'Modo de uso',
              subtitle: settings.mode == UsageMode.free
                  ? 'Gratis (manual)'
                  : 'Con IA: escribir o hablar normal',
              page: (_) => _ModePage(settings: settings),
            ),
            _MenuItem(
              icon: Icons.auto_awesome,
              title: 'Inteligencia artificial',
              subtitle: settings.hasKey(provider.id)
                  ? '${provider.name} · ${suggested[model] ?? model} · clave cargada'
                  : '${provider.name} · falta la clave',
              warn:
                  settings.mode == UsageMode.ai &&
                  !settings.hasKey(provider.id),
              page: (_) => _Page(
                title: 'Inteligencia artificial',
                child: AiSection(settings: settings),
              ),
            ),
            _MenuItem(
              icon: Icons.bar_chart,
              title: 'Consumo de IA',
              subtitle: 'Gasto por día y saldo estimado',
              page: (_) => _Page(
                title: 'Consumo de IA',
                child: UsageSection(settings: settings),
              ),
            ),
            _MenuItem(
              icon: Icons.language,
              title: 'Idioma',
              subtitle: language,
              page: (_) => _LanguagePage(settings: settings),
            ),
            _MenuItem(
              icon: Icons.notifications_outlined,
              title: 'Notificaciones',
              subtitle: 'Permisos, batería y aviso de prueba',
              page: (_) => _Page(
                title: 'Notificaciones',
                child: scope.notifications == null
                    ? const Text(
                        'Las notificaciones solo funcionan en el teléfono.',
                      )
                    : NotificationsSection(service: scope.notifications!),
              ),
            ),
            if (scope.backup != null)
              _MenuItem(
                icon: Icons.add_to_drive,
                title: 'Copia de seguridad',
                subtitle: settings.backupUri == null
                    ? 'Guardar todo en Google Drive'
                    : settings.backupError != null
                    ? 'La última copia falló'
                    : settings.backupLast == null
                    ? 'En Google Drive'
                    : 'Última copia: ${Fmt.when(settings.backupLast!)}',
                warn: settings.backupError != null,
                page: (_) => _Page(
                  title: 'Copia de seguridad',
                  child: BackupSection(backup: scope.backup!),
                ),
              ),
            const _BoxedTile(
              child: ListTile(
                enabled: false,
                leading: CircleAvatar(child: Icon(Icons.schedule)),
                title: Text('Próximamente'),
                subtitle: Text('Sincronizar con Google Calendar'),
              ),
            ),
            const SizedBox(height: 16),
            const _VersionFooter(),
          ],
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
    this.warn = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder page;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _BoxedTile(
      warn: warn,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: warn
              ? scheme.errorContainer
              : scheme.primaryContainer,
          foregroundColor: warn ? scheme.error : scheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: warn ? TextStyle(color: scheme.error) : null,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: page)),
      ),
    );
  }
}

/// Recuadro de cada opción del menú.
class _BoxedTile extends StatelessWidget {
  const _BoxedTile({required this.child, this.warn = false});

  final Widget child;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: warn ? scheme.error : scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// Pantalla de una opción de Configuración.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [child]),
    );
  }
}

class _ModePage extends StatelessWidget {
  const _ModePage({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modo de uso')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ModesHelpView(
          header: [
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Idioma')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => RadioGroup<String>(
          groupValue: settings.language,
          onChanged: (v) {
            if (v != null) settings.setLanguage(v);
          },
          child: ListView(
            children: [
              for (final (code, label) in appLanguages)
                RadioListTile<String>(value: code, title: Text(label)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Es el idioma en el que te entiende y te contesta la IA, y el del dictado por voz. '
                  'Los menús de la app por ahora quedan en español.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
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

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) => Text(
        snapshot.hasData
            ? 'Recordame · versión ${snapshot.data!.version}'
            : 'Recordame',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
