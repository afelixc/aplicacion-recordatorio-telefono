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

class _Message {
  const _Message(this.text, {this.mine = false, this.error = false});

  final String text;
  final bool mine;
  final bool error;
}

enum _Status { thinking, saved, canceled, question, error }

/// Lo último que pasó: se muestra en la solapa "Último recordatorio".
class _Last {
  const _Last(this.status, {this.said, this.reminder, this.text});

  final _Status status;

  /// Lo que dijo o escribió el usuario.
  final String? said;
  final Reminder? reminder;
  final String? text;
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
  final _history = <_Message>[];

  _Last? _last;

  /// El micrófono chico dicta en el recuadro de texto, en vez de mandar.
  bool _dictatingIntoField = false;

  /// Si la IA hizo una pregunta, el pedido anterior para no perder contexto.
  String? _previousRequest;

  static const _examples = [
    'Recordame el viernes a las 9 de la mañana lavar el auto',
    'Todos los lunes y jueves a las 19 ir al gimnasio',
    'Mañana a las 20 llamar a Juan',
  ];

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
    setState(() {
      _history.add(_Message(text, mine: true));
      _last = _Last(_Status.thinking, said: text);
    });

    final request = _previousRequest == null
        ? text
        : 'Pedido anterior: $_previousRequest\nRespuesta del usuario: $text';
    final repo = AppScope.of(context).reminders;
    try {
      final interpreter = await _interpreter();
      final result = await interpreter.interpret(request);
      if (!mounted) return;
      _recordUsage(interpreter, result.usage);
      if (result.ok) {
        // Queda guardado y activo enseguida; después se puede modificar o cancelar.
        _previousRequest = null;
        final saved = await repo.save(result.reminder!);
        _show(
          _Last(_Status.saved, said: text, reminder: saved),
          'Listo ✓ "${saved.title}", ${describeSchedule(saved)}. Quedó activo.',
        );
      } else {
        _previousRequest = request;
        _show(
          _Last(_Status.question, said: text, text: result.message),
          result.message,
        );
      }
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

  void _show(_Last last, String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _last = last;
      _history.add(_Message(message, error: error));
    });
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

  Future<void> _modify(Reminder r) async {
    final repo = AppScope.of(context).reminders;
    await showReminderEditor(context, reminder: r);
    final updated = await repo.getById(r.id!);
    if (!mounted || updated == null) return;
    setState(
      () => _last = _Last(_Status.saved, said: _last?.said, reminder: updated),
    );
  }

  Future<void> _cancel(Reminder r) async {
    await AppScope.of(context).reminders.delete(r.id!);
    _show(
      _Last(_Status.canceled, said: _last?.said, reminder: r),
      'Cancelado: "${r.title}".',
    );
  }

  Future<void> _restore(Reminder r) async {
    final saved = await AppScope.of(context).reminders.save(r);
    _show(
      _Last(_Status.saved, said: _last?.said, reminder: saved),
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
                examples: _examples,
                onExample: _send,
                onManual: () => showReminderEditor(context),
                onModify: _modify,
                onCancel: _cancel,
                onRestore: _restore,
              ),
              _HistoryView(messages: _history),
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

/// Solapa "Último recordatorio": lo último que se pidió y cómo quedó.
class _LastView extends StatelessWidget {
  const _LastView({
    required this.last,
    required this.providerName,
    required this.examples,
    required this.onExample,
    required this.onManual,
    required this.onModify,
    required this.onCancel,
    required this.onRestore,
  });

  final _Last? last;
  final String providerName;
  final List<String> examples;
  final ValueChanged<String> onExample;
  final VoidCallback onManual;
  final ValueChanged<Reminder> onModify;
  final ValueChanged<Reminder> onCancel;
  final ValueChanged<Reminder> onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = this.last;

    if (last == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Tocá el micrófono y decime qué querés que te recuerde y cuándo.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text('Por ejemplo:', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in examples)
                ActionChip(label: Text(e), onPressed: () => onExample(e)),
              ActionChip(
                avatar: const Icon(Icons.edit_note, size: 18),
                label: const Text('Cargar a mano'),
                onPressed: onManual,
              ),
            ],
          ),
        ],
      );
    }

    final said = last.said;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (said != null) ChatBubble(text: said, mine: true),
        switch (last.status) {
          _Status.thinking => Row(
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
          _Status.question => ChatBubble(text: last.text ?? ''),
          _Status.error => ChatBubble(text: last.text ?? '', error: true),
          _Status.saved => _ReminderCard(
            reminder: last.reminder!,
            active: true,
            actions: [
              OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
                onPressed: () => onCancel(last.reminder!),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit),
                label: const Text('Modificar'),
                onPressed: () => onModify(last.reminder!),
              ),
            ],
          ),
          _Status.canceled => _ReminderCard(
            reminder: last.reminder!,
            active: false,
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Volver a activarlo'),
                onPressed: () => onRestore(last.reminder!),
              ),
            ],
          ),
        },
        if (last.status == _Status.question)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Respondeme con el micrófono o escribiendo.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.active,
    required this.actions,
  });

  final Reminder reminder;
  final bool active;
  final List<Widget> actions;

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 8),
            Text(
              reminder.title,
              style: theme.textTheme.titleLarge?.copyWith(
                decoration: active ? null : TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(height: 4),
            Text(describeSchedule(reminder)),
            if (next != null) Text('Próximo: ${Fmt.when(next)}'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

/// Solapa "Chat completo": todo lo hablado en esta sesión.
class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.messages});

  final List<_Message> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Text('Todavía no hablamos.'));
    }
    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      children: [
        for (final m in messages.reversed)
          ChatBubble(text: m.text, mine: m.mine, error: m.error),
      ],
    );
  }
}

/// Mientras se habla: lo que se va entendiendo, Cancelar y Enviar.
class _TalkingPanel extends StatelessWidget {
  const _TalkingPanel({
    required this.text,
    required this.onCancel,
    required this.onSend,
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.mic, color: scheme.error),
            const SizedBox(width: 6),
            Text(
              'Te escucho… hablá tranquilo, no se corta.',
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 56, maxHeight: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              text.isEmpty ? '…' : text,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Cancelar'),
                onPressed: onCancel,
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
                onPressed: onSend,
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
          width: 72,
          height: 72,
          child: FloatingActionButton.large(
            heroTag: 'mic',
            tooltip: 'Hablar',
            backgroundColor: scheme.secondary,
            foregroundColor: scheme.onSecondary,
            onPressed: busy || dictatingIntoField ? null : onTalk,
            child: const Icon(Icons.mic, size: 34),
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
