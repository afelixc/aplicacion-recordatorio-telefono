import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../help/modes_help.dart';
import '../home/home_shell.dart';
import '../notebook/notebook_page.dart';
import '../notebook/notes.dart';
import '../reminders/reminder_form.dart';
import 'ai_chat.dart';

/// Pestaña principal. Con la IA lista muestra el chat; si no, el formulario
/// para cargar a mano (modo gratis).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        children: [
          ValueListenableBuilder(
            valueListenable: chatCompact,
            builder: (context, compact, _) => PlanBar(
              settings: settings,
              compact: compact && settings.aiReady,
            ),
          ),
          Expanded(
            child: settings.aiReady
                ? AiChat(key: ValueKey(settings.providerId), settings: settings)
                : const _ManualEntry(),
          ),
        ],
      ),
    );
  }
}

/// "Tu plan: Gratis | Con IA". El activo se ve resaltado y el otro en gris.
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.settings, this.compact = false});

  final AppSettings settings;

  /// Más chica mientras se ve un recordatorio recién guardado.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final missingKey = settings.mode == UsageMode.ai && !settings.aiReady;
    final segStyle = compact ? const TextStyle(fontSize: 12) : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 0 : 4, 8, compact ? 0 : 4),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Tu plan:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: compact ? 12 : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<UsageMode>(
                  key: const Key('plan-selector'),
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: compact
                        ? const VisualDensity(vertical: -4)
                        : VisualDensity.compact,
                    tapTargetSize: compact
                        ? MaterialTapTargetSize.shrinkWrap
                        : null,
                    selectedBackgroundColor: scheme.primary,
                    selectedForegroundColor: scheme.onPrimary,
                    foregroundColor: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                  segments: [
                    ButtonSegment(
                      value: UsageMode.free,
                      label: Text('Gratis', style: segStyle),
                    ),
                    ButtonSegment(
                      value: UsageMode.ai,
                      label: Text('Con IA', style: segStyle),
                    ),
                  ],
                  selected: {settings.mode},
                  onSelectionChanged: (s) => settings.setMode(s.first),
                ),
              ),
              IconButton(
                tooltip: '¿Cómo funciona?',
                visualDensity: compact
                    ? const VisualDensity(vertical: -4)
                    : null,
                iconSize: compact ? 20 : null,
                icon: const Icon(Icons.help_outline),
                onPressed: () => showModesHelp(context),
              ),
            ],
          ),
          if (missingKey)
            Row(
              children: [
                Icon(Icons.key_off, size: 18, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Falta tu clave de IA.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                TextButton(
                  onPressed: () => HomeShell.goToTab(context, 'Configuración'),
                  child: const Text('Cargarla'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ManualEntry extends StatefulWidget {
  const _ManualEntry();

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
  // Cambiar la clave reinicia el formulario después de guardar.
  int _formVersion = 0;
  String? _lastSaved;
  final _formKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = AppScope.of(context).reminders;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        // Los mismos dos botones que en el Chat con IA.
        ListenableBuilder(
          listenable: AppScope.of(context).settings,
          builder: (context, _) {
            final settings = AppScope.of(context).settings;
            return NotebookShortcuts(
              notebookToDo: notebookToDo(settings.folders),
              onManual: () => _formKey.currentContext == null
                  ? null
                  : Scrollable.ensureVisible(
                      _formKey.currentContext!,
                      duration: const Duration(milliseconds: 300),
                    ),
              onNotebook: () => openNotebook(context, settings),
            );
          },
        ),
        const SizedBox(height: 8),
        if (_lastSaved != null) ChatBubble(text: _lastSaved!),
        const SizedBox(height: 8),
        Card(
          key: _formKey,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ReminderForm(
              key: ValueKey(_formVersion),
              submitLabel: 'Guardar recordatorio',
              onSubmit: (r) async {
                await repo.save(r);
                setState(() {
                  _formVersion++;
                  _lastSaved =
                      'Guardado ✓ "${r.title}", ${describeSchedule(r)}.';
                });
                // Arriba, para que se vea el "Guardado ✓".
                if (_scroll.hasClients) {
                  await _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Globo de mensaje del chat.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    this.mine = false,
    this.error = false,
    this.at,
  });

  final String text;
  final bool mine;
  final bool error;

  /// Hora en que se mandó (en el chat completo).
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine
        ? scheme.primary
        : error
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final fg = mine
        ? scheme.onPrimary
        : error
        ? scheme.onErrorContainer
        : scheme.onSurface;
    const r = Radius.circular(16);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 8,
          left: mine ? 48 : 0,
          right: mine ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: r,
            topRight: r,
            bottomLeft: mine ? r : const Radius.circular(4),
            bottomRight: mine ? const Radius.circular(4) : r,
          ),
        ),
        child: at == null
            ? Text(text, style: TextStyle(color: fg))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text(text, style: TextStyle(color: fg)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Fmt.time(at!),
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
