import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../data/reminder.dart';
import '../../data/usage.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_providers.dart';
import '../ai/pricing.dart';
import '../ai/reminder_interpreter.dart';
import '../reminders/reminder_editor.dart';
import 'chat_screen.dart';
import 'dictation.dart';
import '../notebook/notebook_page.dart';
import 'examples_sheet.dart';

enum _Status { thinking, saved, question, error }

/// Un recordatorio que armó la IA y si sigue activo o se canceló.
class _Item {
  const _Item(this.reminder, {this.active = true});

  final Reminder reminder;
  final bool active;
}

/// Lo último que pasó: se muestra en la solapa "Último recordatorio".
class _Last {
  const _Last(this.status, {this.said, this.items = const [], this.text});

  final _Status status;

  /// Lo que dijo o escribió el usuario.
  final String? said;

  /// Los recordatorios que se guardaron (hasta dos).
  final List<_Item> items;

  /// La pregunta o el error; con [items], la pregunta por el que faltó.
  final String? text;

  _Last withItem(int i, _Item item) =>
      _Last(status, said: said, items: [...items]..[i] = item, text: text);
}

/// Chat con IA: el usuario habla o escribe, la IA arma el recordatorio y queda
/// guardado y activo enseguida; después se puede modificar o cancelar.
class AiChat extends StatefulWidget {
  const AiChat({super.key, required this.settings, this.interpreter});

  final AppSettings settings;

  /// Para las pruebas; si es null se arma con la configuración.
  final ReminderInterpreter? interpreter;

  @override
  State<AiChat> createState() => _AiChatState();
}

class _AiChatState extends State<AiChat> with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _dictation = Dictation();
  late final _tabs = TabController(length: 2, vsync: this);
  List<ChatEntry> get _history => widget.settings.chatHistory;

  _Last? _last;

  /// El micrófono chico dicta en el recuadro de texto, en vez de mandar.
  bool _dictatingIntoField = false;

  /// Si la IA hizo una pregunta, el pedido anterior para no perder contexto.
  String? _previousRequest;

  /// Los que ya se guardaron de ese pedido, para no repetirlos al completar.
  final _alreadySaved = <String>{};

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_onDictation);
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictation);
    _dictation.dispose();
    _input.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onDictation() {
    if (_dictatingIntoField && _dictation.active) {
      _input.text = _dictation.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() {});
  }

  bool get _thinking => _last?.status == _Status.thinking;

  Future<ReminderInterpreter> _interpreter() async {
    if (widget.interpreter != null) return widget.interpreter!;
    final s = widget.settings;
    final provider =
        AppScope.of(context).aiProviderOverride ?? providerById(s.providerId);
    final key = await s.keys.read(provider.id);
    if (key == null) {
      throw const AiException('Falta la clave. Cargala en Configuración.');
    }
    return ReminderInterpreter(
      provider: provider,
      apiKey: key,
      model: s.modelFor(provider.id) ?? provider.defaultModel,
      language: s.language,
    );
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _thinking) return;
    _input.clear();
    _tabs.animateTo(0);
    widget.settings.addChat(ChatEntry(text, mine: true, at: DateTime.now()));
    setState(() => _last = _Last(_Status.thinking, said: text));

    final request = _previousRequest == null
        ? text
        : 'Pedido anterior: $_previousRequest\nRespuesta del usuario: $text';
    final repo = AppScope.of(context).reminders;
    try {
      final interpreter = await _interpreter();
      final result = await interpreter.interpret(request);
      if (!mounted) return;
      _recordUsage(interpreter, result.usage);
      // Los completos quedan guardados y activos enseguida; después se pueden
      // modificar o cancelar. Si a otro le faltaba algo, se pregunta.
      final saved = <Reminder>[];
      for (final r in result.reminders) {
        if (_alreadySaved.contains(r.title.toLowerCase())) continue;
        saved.add(await repo.save(r));
      }
      final question = result.ok ? result.question : result.message;
      final lines = [
        for (final r in saved)
          'Listo ✓ "${r.title}", ${describeSchedule(r)}. Quedó activo.',
        if (result.tooMany)
          'Te anoté los dos primeros: puedo hasta dos por mensaje. '
              'Mandame el resto en otro mensaje.',
        ?question,
      ];
      if (question != null && _previousRequest != null && saved.isEmpty) {
        // Otra vuelta sin entenderse: se suma lo dicho sin anidar
        // "Pedido anterior" dentro de otro (eso la confundía).
        _previousRequest = '$_previousRequest\nDespués dijo: $text';
      } else if (question != null) {
        _alreadySaved.addAll(saved.map((r) => r.title.toLowerCase()));
        _previousRequest = _alreadySaved.isEmpty
            ? request
            : '$request\nYa quedaron guardados, no los vuelvas a crear: '
                  '${_alreadySaved.join(', ')}.';
      } else {
        _previousRequest = null;
        _alreadySaved.clear();
      }
      if (lines.isEmpty) lines.add('Eso ya lo tenía anotado.');
      _show(
        saved.isEmpty
            ? _Last(_Status.question, said: text, text: lines.join('\n'))
            : _Last(
                _Status.saved,
                said: text,
                items: [for (final r in saved) _Item(r)],
                text: question,
              ),
        lines.join('\n'),
      );
    } on AiException catch (e) {
      _show(
        _Last(_Status.error, said: text, text: e.message),
        e.message,
        error: true,
      );
    } catch (_) {
      const message =
          'No me pude conectar. Revisá tu internet, o cargalo a mano.';
      _show(
        _Last(_Status.error, said: text, text: message),
        message,
        error: true,
      );
    }
  }

  /// Olvida la pregunta pendiente: el próximo mensaje es un pedido nuevo.
  void _startOver() {
    _previousRequest = null;
    _alreadySaved.clear();
    setState(() => _last = null);
    widget.settings.addChat(
      ChatEntry(
        'Listo, empezamos de nuevo. Decime qué querés que te recuerde y cuándo.',
        at: DateTime.now(),
      ),
    );
  }

  void _show(_Last last, String message, {bool error = false}) {
    if (!mounted) return;
    widget.settings.addChat(
      ChatEntry(message, error: error, at: DateTime.now()),
    );
    setState(() => _last = last);
  }

  /// Anota la consulta para la sección de consumo de Configuración.
  void _recordUsage(ReminderInterpreter interpreter, AiResult? usage) {
    if (usage == null) return;
    final price = priceFor(interpreter.model);
    AppScope.of(context).usage.record(
      UsageRecord(
        at: DateTime.now(),
        provider: interpreter.provider.id,
        model: interpreter.model,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        costUsd: price?.cost(usage.inputTokens, usage.outputTokens),
      ),
    );
  }

  Future<void> _modify(int i) async {
    final repo = AppScope.of(context).reminders;
    final r = _last!.items[i].reminder;
    await showReminderEditor(context, reminder: r);
    final updated = await repo.getById(r.id!);
    if (!mounted || updated == null || _last == null) return;
    setState(() => _last = _last!.withItem(i, _Item(updated)));
  }

  Future<void> _cancel(int i) async {
    final r = _last!.items[i].reminder;
    await AppScope.of(context).reminders.delete(r.id!);
    _show(
      _last!.withItem(i, _Item(r, active: false)),
      'Cancelado: "${r.title}".',
    );
  }

  Future<void> _restore(int i) async {
    final r = _last!.items[i].reminder;
    final saved = await AppScope.of(context).reminders.save(r);
    _show(
      _last!.withItem(i, _Item(saved)),
      'Lo volví a activar: "${saved.title}".',
    );
  }

  Future<void> _startTalking() async {
    _dictatingIntoField = false;
    final ok = await _dictation.start(language: widget.settings.language);
    if (!ok) _micError();
  }

  Future<void> _sendTalking() async => _send(await _dictation.finish());

  Future<void> _toggleFieldDictation() async {
    if (_dictation.active) {
      await _dictation.finish();
      setState(() => _dictatingIntoField = false);
      return;
    }
    _dictatingIntoField = true;
    final ok = await _dictation.start(
      language: widget.settings.language,
      initialText: _input.text,
    );
    if (!ok) {
      _dictatingIntoField = false;
      _micError();
    }
  }

  void _micError() => _show(
    _Last(
      _Status.error,
      text:
          'No pude usar el micrófono. Permití el acceso al micrófono para Recordame '
          'en los ajustes del teléfono, o escribilo.',
    ),
    'No pude usar el micrófono.',
    error: true,
  );

  @override
  Widget build(BuildContext context) {
    final talking = _dictation.active && !_dictatingIntoField;
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Último recordatorio'),
            Tab(text: 'Chat completo'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _LastView(
                last: _last,
                providerName: providerById(widget.settings.providerId).name,
                onExamples: () => showExamples(context),
                onManual: () => showReminderEditor(context),
                onNotebook: () => openNotebook(context, widget.settings),
                onModify: _modify,
                onCancel: _cancel,
                onRestore: _restore,
                onStartOver: _startOver,
              ),
              _HistoryView(
                messages: _history,
                onClear: () async {
                  await widget.settings.clearChat();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        Material(
          elevation: 3,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: talking
                  ? _TalkingPanel(
                      text: _dictation.text,
                      onCancel: _dictation.cancel,
                      onSend: _sendTalking,
                    )
                  : _Composer(
                      input: _input,
                      busy: _thinking,
                      dictatingIntoField: _dictatingIntoField,
                      onTalk: _startTalking,
                      onFieldMic: _toggleFieldDictation,
                      onSend: () async {
                        if (_dictatingIntoField) await _toggleFieldDictation();
                        _send(_input.text);
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Solapa "Último recordatorio": lo último que se pidió y cómo quedó, todo
/// a la vista sin tener que deslizar.
class _LastView extends StatelessWidget {
  const _LastView({
    required this.last,
    required this.providerName,
    required this.onExamples,
    required this.onManual,
    required this.onNotebook,
    required this.onModify,
    required this.onCancel,
    required this.onRestore,
    required this.onStartOver,
  });

  final _Last? last;
  final String providerName;
  final VoidCallback onExamples;
  final VoidCallback onManual;
  final VoidCallback onNotebook;
  final ValueChanged<int> onModify;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onRestore;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = this.last;
    final startOver = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('start-over'),
        icon: const Icon(Icons.restart_alt),
        label: const Text('Empezar de nuevo (olvidar esta pregunta)'),
        onPressed: onStartOver,
      ),
    );

    final shortcuts = Row(
      children: [
        Expanded(
          child: _BoxButton(
            icon: Icons.lightbulb_outline,
            label: 'Ejemplos',
            onPressed: onExamples,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BoxButton(
            icon: Icons.edit_note,
            label: 'Cargar a mano',
            onPressed: onManual,
            filled: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BoxButton(
            key: const Key('open-notebook'),
            icon: Icons.menu_book_outlined,
            label: 'Libreta',
            onPressed: onNotebook,
          ),
        ),
      ],
    );

    if (last == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tocá el micrófono y decime qué querés que te recuerde y cuándo.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          shortcuts,
        ],
      );
    }

    final said = last.said;
    final saidLine = said == null
        ? null
        : Text(
            'Dijiste: “$said”',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        switch (last.status) {
          _Status.thinking => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?saidLine,
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Pensando con $providerName…'),
                ],
              ),
            ],
          ),
          _Status.question || _Status.error => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (saidLine != null) ...[saidLine, const SizedBox(height: 8)],
              ChatBubble(
                text: last.text ?? '',
                error: last.status == _Status.error,
              ),
              if (last.status == _Status.question) ...[
                Text(
                  'Respondeme con el micrófono o escribiendo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                startOver,
              ],
            ],
          ),
          _Status.saved => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, item) in last.items.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _ReminderCard(
                  reminder: item.reminder,
                  active: item.active,
                  // Lo que dijo va arriba de todo, en la primera tarjeta.
                  said: i == 0 ? saidLine : null,
                  actions: item.active
                      ? [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text('Cancelar'),
                              onPressed: () => onCancel(i),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              icon: const Icon(Icons.edit),
                              label: const Text('Modificar'),
                              onPressed: () => onModify(i),
                            ),
                          ),
                        ]
                      : [
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.undo),
                              label: const Text('Volver a activarlo'),
                              onPressed: () => onRestore(i),
                            ),
                          ),
                        ],
                ),
              ],
              // Al otro le faltaba algo: la pregunta, debajo.
              if (last.text != null) ...[
                const SizedBox(height: 8),
                ChatBubble(text: last.text!),
                Text(
                  'Respondeme con el micrófono o escribiendo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                startOver,
              ],
            ],
          ),
        },
        const SizedBox(height: 12),
        shortcuts,
      ],
    );
  }
}

/// Botón con recuadro (Ejemplos, Cargar a mano).
class _BoxButton extends StatelessWidget {
  const _BoxButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Fondo amarillo claro (el amarillo fuerte queda para el micrófono).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        backgroundColor: filled
            ? scheme.secondary.withValues(alpha: 0.18)
            : null,
        foregroundColor: filled ? scheme.onSurface : null,
        side: BorderSide(
          color: filled
              ? scheme.secondary.withValues(alpha: 0.7)
              : scheme.primary.withValues(alpha: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      // Ícono arriba y texto abajo: entran tres en una fila.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, maxLines: 2),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.active,
    required this.actions,
    this.said,
  });

  final Reminder reminder;
  final bool active;
  final List<Widget> actions;
  final Widget? said;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = reminder.repeats ? reminder.nextOccurrence() : null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: active ? Colors.green : scheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (said != null) ...[said!, const SizedBox(height: 8)],
            Row(
              children: [
                Icon(
                  active ? Icons.check_circle : Icons.cancel,
                  color: active ? Colors.green : scheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  active ? 'Activo' : 'Cancelado',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: active ? Colors.green : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reminder.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                decoration: active ? null : TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(height: 2),
            Text(describeSchedule(reminder)),
            if (next != null) Text('Próximo: ${Fmt.when(next)}'),
            const SizedBox(height: 10),
            Row(children: actions),
          ],
        ),
      ),
    );
  }
}

/// Solapa "Chat completo": todo lo hablado, guardado en el teléfono.
class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.messages, required this.onClear});

  final List<ChatEntry> messages;
  final VoidCallback onClear;

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar el chat?'),
        content: const Text(
          'Se borra solo la conversación. Los recordatorios quedan como están.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar chat'),
          ),
        ],
      ),
    );
    if (ok == true) onClear();
  }

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Text('Todavía no hablamos.'));
    }
    final theme = Theme.of(context);
    final items = <Widget>[];
    DateTime? day;
    for (final m in messages) {
      final d = DateTime(m.at.year, m.at.month, m.at.day);
      if (d != day) {
        day = d;
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                Fmt.day(d),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }
      items.add(ChatBubble(text: m.text, mine: m.mine, error: m.error));
    }
    items.add(
      Center(
        child: TextButton.icon(
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Borrar chat'),
          onPressed: () => _confirmClear(context),
        ),
      ),
    );
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      children: items.reversed.toList(),
    );
  }
}

/// Mientras se habla: como grabar un audio. Se ve que está grabando y el
/// tiempo; lo que se va entendiendo queda escondido (se puede ver si se quiere).
class _TalkingPanel extends StatefulWidget {
  const _TalkingPanel({
    required this.text,
    required this.onCancel,
    required this.onSend,
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  State<_TalkingPanel> createState() => _TalkingPanelState();
}

class _TalkingPanelState extends State<_TalkingPanel> {
  final _started = DateTime.now();
  late final Timer _timer;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final elapsed = DateTime.now().difference(_started);
    final clock =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    // El punto rojo titila como en las grabadoras.
    final blink = elapsed.inMilliseconds ~/ 500 % 2 == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AnimatedOpacity(
              opacity: blink ? 1 : 0.25,
              duration: const Duration(milliseconds: 300),
              child: Icon(Icons.fiber_manual_record, color: scheme.error),
            ),
            const SizedBox(width: 6),
            Text('Grabando  $clock', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _showText = !_showText),
              child: Text(_showText ? 'Ocultar texto' : 'Ver texto'),
            ),
          ],
        ),
        Text(
          'Hablá tranquilo, no se corta. Cuando termines tocá Enviar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (_showText) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 48, maxHeight: 120),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(widget.text.isEmpty ? '…' : widget.text),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
                onPressed: widget.onCancel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send),
                label: const Text('Enviar'),
                onPressed: widget.onSend,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botón grande para hablar y, debajo, un recuadro chico para escribir.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.busy,
    required this.dictatingIntoField,
    required this.onTalk,
    required this.onFieldMic,
    required this.onSend,
  });

  final TextEditingController input;
  final bool busy;
  final bool dictatingIntoField;
  final VoidCallback onTalk;
  final VoidCallback onFieldMic;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: FloatingActionButton.large(
            heroTag: 'mic',
            tooltip: 'Hablar',
            backgroundColor: scheme.secondary,
            foregroundColor: scheme.onSecondary,
            onPressed: busy || dictatingIntoField ? null : onTalk,
            child: const Icon(Icons.mic, size: 30),
          ),
        ),
        const SizedBox(height: 2),
        Text('Tocá para hablar', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('chat-input'),
                controller: input,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'O escribilo acá…',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  suffixIcon: IconButton(
                    tooltip: dictatingIntoField
                        ? 'Dejar de dictar'
                        : 'Dictar en el recuadro',
                    icon: Icon(
                      dictatingIntoField ? Icons.stop_circle : Icons.mic_none,
                      color: dictatingIntoField ? scheme.error : null,
                    ),
                    onPressed: busy ? null : onFieldMic,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.send, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
