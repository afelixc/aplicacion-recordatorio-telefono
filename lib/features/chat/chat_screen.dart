import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
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
      builder: (context, _) => settings.aiReady
          ? AiChat(key: ValueKey(settings.providerId), settings: settings)
          : _ManualEntry(missingKey: settings.mode == UsageMode.ai),
    );
  }
}

class _ManualEntry extends StatefulWidget {
  const _ManualEntry({required this.missingKey});

  final bool missingKey;

  @override
  State<_ManualEntry> createState() => _ManualEntryState();
}

class _ManualEntryState extends State<_ManualEntry> {
  // Cambiar la clave reinicia el formulario después de guardar.
  int _formVersion = 0;
  String? _lastSaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = AppScope.of(context).reminders;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ChatBubble(
          text: widget.missingKey
              ? 'Para escribirme o hablarme de corrido, cargá tu clave de IA en Configuración → Inteligencia artificial. '
                    'Mientras tanto, podés cargar el recordatorio acá abajo.'
              : 'Hola. Cargá qué querés que te recuerde y cuándo. '
                    'Si activás el modo IA en Configuración, me lo podés escribir o decir de corrido.',
        ),
        if (_lastSaved != null) ChatBubble(text: _lastSaved!),
        const SizedBox(height: 8),
        Card(
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
  });

  final String text;
  final bool mine;
  final bool error;

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
        child: Text(text, style: TextStyle(color: fg)),
      ),
    );
  }
}
