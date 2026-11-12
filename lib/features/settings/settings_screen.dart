import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../ai/ai_providers.dart';
import '../help/modes_help.dart';
import 'ai_section.dart';
import 'backup_section.dart';
import 'calendar_section.dart';
import 'colors_page.dart';
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
              icon: Icons.palette_outlined,
              title: 'Colores',
              subtitle: 'Día y noche, la app, almanaque, listado e ícono',
              page: (_) => const ColorsPage(),
            ),
            _MenuItem(
              icon: Icons.notifications_outlined,
              title: 'Notificaciones',
              subtitle: 'Sonido, prioridades y permisos',
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
            if (scope.calendar != null)
              _MenuItem(
                icon: Icons.calendar_month,
                title: 'Google Calendar',
                subtitle: switch ((
                  settings.calendarSend,
                  settings.calendarAuto,
                )) {
                  (true, true) => 'Sincronizado en los dos sentidos',
                  (true, false) => 'Envía tus recordatorios al calendario',
                  (false, true) => 'Trae lo nuevo del calendario',
                  _ => 'Traer y enviar al calendario del teléfono',
                },
                page: (_) => _Page(
                  title: 'Google Calendar',
                  child: CalendarSection(sync: scope.calendar!),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _BoxedTile(
      warn: warn,
      child: InkWell(
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: page)),
        // Todos los recuadros del mismo tamaño (pedido del usuario): el
        // título y la explicación en un renglón cada uno; si no entran, la
        // letra se achica un poco.
        child: SizedBox(
          height: menuItemHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: warn
                      ? scheme.errorContainer
                      : scheme.primaryContainer,
                  foregroundColor: warn
                      ? scheme.error
                      : scheme.onPrimaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FitLine(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _FitLine(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: warn ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Alto de cada recuadro del menú de Configuración.
const menuItemHeight = 72.0;

/// Un renglón: si no entra, la letra se achica (hasta cierto punto; después
/// se corta con "…").
class _FitLine extends StatelessWidget {
  const _FitLine(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final base = style ?? DefaultTextStyle.of(context).style;
      final size = base.fontSize ?? 14;
      final scaler = MediaQuery.textScalerOf(context);
      // Se prueba de a medio punto hasta que entre (como mucho un 25 % menos).
      var fit = size;
      while (fit > size * 0.75) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: base.copyWith(fontSize: fit),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final fits = tp.width <= c.maxWidth;
        tp.dispose();
        if (fits) break;
        fit -= 0.5;
      }
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base.copyWith(fontSize: fit),
      );
    },
  );
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
