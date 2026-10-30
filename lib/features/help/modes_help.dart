import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/settings.dart';
import '../home/home_shell.dart';

/// Solapita chica arriba del chat: muestra el modo actual y, al tocarla,
/// la explicación completa.
class ModeChip extends StatelessWidget {
  const ModeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, warn) = switch ((settings.mode, settings.aiReady)) {
      (UsageMode.free, _) => (
        'Gratis · ¿Querés usar IA?',
        Icons.edit_note,
        false,
      ),
      (UsageMode.ai, false) => ('Con IA · falta la clave', Icons.key_off, true),
      (UsageMode.ai, true) => ('Con IA', Icons.auto_awesome, false),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        key: const Key('mode-chip'),
        avatar: Icon(icon, size: 18, color: warn ? scheme.error : null),
        label: Text(label),
        visualDensity: VisualDensity.compact,
        side: warn ? BorderSide(color: scheme.error) : null,
        onPressed: () => showModesHelp(context),
      ),
    );
  }
}

/// Explicación completa: gratis vs. con IA, por qué hace falta una clave,
/// cuánto sale y cómo conseguirla.
Future<void> showModesHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => _ModesHelp(
        scroll: scroll,
        onGoToSettings: () {
          Navigator.pop(sheetContext);
          // El context de quien abrió la hoja está dentro de las pestañas.
          HomeShell.goToTab(context, 'Configuración');
        },
      ),
    ),
  );
}

class _ModesHelp extends StatelessWidget {
  const _ModesHelp({required this.scroll, required this.onGoToSettings});

  final ScrollController scroll;
  final VoidCallback onGoToSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget h(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget p(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            child: Text('$n', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Text('Dos formas de usar Recordame', style: theme.textTheme.titleLarge),
        h('Gratis'),
        p(
          'Cargás cada recordatorio con un formulario: qué, día, hora y si se repite. '
          'No necesita internet ni cuenta, y no cuesta nada.',
        ),
        h('Con IA'),
        p(
          'Le escribís o le hablás normal, por ejemplo: "Recordame el viernes a las 9 de la mañana lavar el auto". '
          'La inteligencia artificial entiende el día, la hora y si se repite, y te lo muestra para que lo confirmes o lo corrijas.',
        ),
        h('¿Por qué hace falta una clave?'),
        p(
          'La IA no corre en tu teléfono: funciona en los servidores de la empresa que la ofrece (Anthropic, OpenAI o Google). '
          'Cada consulta cuesta una fracción de centavo, y cada persona la paga con su propia cuenta. '
          'La "clave de API" es como una contraseña que le dice a la empresa a qué cuenta cobrarle.',
        ),
        p(
          'Recordame no cobra nada ni se queda con tu clave: se guarda cifrada solo en tu teléfono.',
        ),
        p(
          'Las notificaciones, el listado y el almanaque funcionan sin internet y no gastan saldo. '
          'La IA solo se usa para entender lo que escribís o decís.',
        ),
        h('Ojo: tu plan de Claude no sirve para esto'),
        p(
          'La suscripción de Claude (claude.ai, la app para chatear) es una cosa y la API es otra, con saldo aparte. '
          'Para Recordame necesitás saldo cargado en la API.',
        ),
        h('¿Cuánto sale?'),
        p(
          'Con Claude Haiku 5.5 (el que viene elegido), cada recordatorio cuesta aproximadamente entre una centésima y una décima de centavo de dólar. '
          'Con US\$ 5 de saldo alcanza para miles de recordatorios. En Configuración → Consumo de IA ves lo que vas gastando.',
        ),
        h('Cómo conseguir la clave de Claude'),
        step(
          1,
          'Entrá a console.anthropic.com (puede llevarte a platform.claude.com, es lo mismo) e iniciá sesión.',
        ),
        step(
          2,
          'En "Billing" (Facturación), agregá una tarjeta y cargá saldo. Con el mínimo alcanza.',
        ),
        step(
          3,
          'En "API Keys", tocá "Create Key" y ponele de nombre "Recordame".',
        ),
        step(
          4,
          'Copiá la clave (empieza con sk-ant-). Se muestra una sola vez: si ya tenías una y no la guardaste, creá una nueva.',
        ),
        step(
          5,
          'En Recordame: Configuración → Con IA → pegá la clave → "Guardar y probar".',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir la página de claves'),
              onPressed: () => launchUrl(
                Uri.parse('https://console.anthropic.com/settings/keys'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Ir a Configuración'),
              onPressed: onGoToSettings,
            ),
          ],
        ),
        h('¿Y OpenAI o Gemini?'),
        p(
          'También funcionan. Los pasos para cada uno están en Configuración, en "Cómo conseguir tu clave".',
        ),
      ],
    );
  }
}
