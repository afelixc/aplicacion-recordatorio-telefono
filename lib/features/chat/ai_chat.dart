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
import '../notebook/notes.dart';
import 'examples_sheet.dart';
import 'talking_panel.dart';
import '../notifications/priority_config.dart';
import '../settings/priorities_page.dart';

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
/// Prendido mientras se ve un recordatorio recién guardado: la pantalla del
/// Chat se achica (barra del plan, solapas, micrófono) para que entre la
/// tarjeta entera con la prioridad, sin deslizar (pedido del usuario).
final chatCompact = ValueNotifier<bool>(false);

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
    chatCompact.value = false;
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
    // Se esconde el teclado para que se vea la tarjeta entera.
    FocusManager.instance.primaryFocus?.unfocus();
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

  /// Cambia la prioridad o el "sonar en silencio" de uno ya guardado.
  Future<void> _setPriority(
    int i, {
    ReminderPriority? priority,
    bool? loud,
  }) async {
    final r = _last!.items[i].reminder.copyWith(priority: priority, loud: loud);
    setState(() => _last = _last!.withItem(i, _Item(r)));
    await AppScope.of(context).reminders.save(r);
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
    final compact =
        _last?.status == _Status.saved && _last!.items.any((i) => i.active);
    if (chatCompact.value != compact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chatCompact.value = compact;
      });
    }
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          labelStyle: compact ? const TextStyle(fontSize: 14) : null,
          unselectedLabelStyle: compact ? const TextStyle(fontSize: 14) : null,
          tabs: [
            Tab(text: 'Último recordatorio', height: compact ? 32 : null),
            Tab(text: 'Chat completo', height: compact ? 32 : null),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              ListenableBuilder(
                listenable: widget.settings,
                builder: (context, _) => _LastView(
                  last: _last,
                  notebookToDo: notebookToDo(widget.settings.folders),
                  providerName: providerById(widget.settings.providerId).name,
                  onExamples: () => showExamples(context),
                  onManual: () => showReminderEditor(context),
                  onNotebook: () => openNotebook(context, widget.settings),
                  onModify: _modify,
                  onCancel: _cancel,
                  onRestore: _restore,
                  onPriority: (i, p) => _setPriority(i, priority: p),
                  onLoud: (i, v) => _setPriority(i, loud: v),
                  onStartOver: _startOver,
                ),
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
              padding: EdgeInsets.fromLTRB(12, compact ? 6 : 10, 12, 8),
              child: talking
                  ? TalkingPanel(
                      text: _dictation.text,
                      onCancel: _dictation.cancel,
                      onSend: _sendTalking,
                    )
                  : _Composer(
                      compact: compact,
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
    required this.notebookToDo,
    required this.onModify,
    required this.onCancel,
    required this.onRestore,
    required this.onPriority,
    required this.onLoud,
    required this.onStartOver,
  });

  final _Last? last;
  final String providerName;
  final VoidCallback onExamples;
  final VoidCallback onManual;
  final VoidCallback onNotebook;
  final int notebookToDo;
  final ValueChanged<int> onModify;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onRestore;
  final void Function(int, ReminderPriority) onPriority;
  final void Function(int, bool) onLoud;
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

    // Arriba la frase chica con "Ejemplos" al lado; abajo dos botones
    // grandes iguales, de distinto color, que se agrandan al tocarlos.
    final shortcuts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tocá el micrófono y decime qué querés que te recuerde y '
                'cuándo.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: const VisualDensity(
                  horizontal: -3,
                  vertical: -3,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.lightbulb_outline, size: 14),
              label: const Text('Ejemplos'),
              onPressed: onExamples,
            ),
          ],
        ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _BigButton(
                  icon: Icons.edit_note,
                  label: 'Cargar a mano\nrecordatorios',
                  color: scheme.primary,
                  onPressed: onManual,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigButton(
                  key: const Key('open-notebook'),
                  icon: Icons.menu_book_outlined,
                  label: 'Libreta',
                  badge: ToDoBadge(notebookToDo),
                  big: true,
                  color: const Color(0xFFC98A00),
                  onPressed: onNotebook,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (last == null) {
      return ListView(padding: const EdgeInsets.all(16), children: [shortcuts]);
    }

    final said = last.said;
    final saidLine = said == null
        ? null
        : TapToExpand(
            'Dijiste: “$said”',
            key: const Key('said-line'),
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          );
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                  footer: item.active
                      ? _PriorityPicker(
                          reminder: item.reminder,
                          onPriority: (p) => onPriority(i, p),
                          onLoud: (v) => onLoud(i, v),
                        )
                      : null,
                  actions: item.active
                      ? [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: _smallButton,
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Cancelar', maxLines: 1),
                              onPressed: () => onCancel(i),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: _smallButton,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Modificar', maxLines: 1),
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

/// Botón grande (Cargar a mano / Libreta): al tocarlo se agranda y entra.
class _BigButton extends StatefulWidget {
  const _BigButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.badge,
    this.big = false,
  });

  /// Letra y dibujo un poco más grandes (la Libreta, pedido del usuario).
  final bool big;

  /// Va en el segundo renglón, en lugar de texto (p. ej. "2 por hacer").
  final Widget? badge;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _big = false;

  Future<void> _tap() async {
    setState(() => _big = true);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    widget.onPressed();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _big = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return AnimatedScale(
      scale: _big ? 1.12 : 1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Material(
        color: c.withValues(alpha: 0.12),
        elevation: _big ? 6 : 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: widget.big ? 36 : 30, color: c),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w800,
                    fontSize: widget.big ? 18 : 15,
                  ),
                ),
                if (widget.badge != null) ...[
                  const SizedBox(height: 2),
                  widget.badge!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botones chicos, en un renglón (Cancelar / Modificar).
final _smallButton = ButtonStyle(
  visualDensity: VisualDensity.compact,
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
  ),
);

/// Prioridad del recordatorio (Normal · Media · Alta) y "Sonar aunque esté
/// en silencio", debajo de Cancelar / Modificar.
class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker({
    required this.reminder,
    required this.onPriority,
    required this.onLoud,
  });

  final Reminder reminder;
  final ValueChanged<ReminderPriority> onPriority;
  final ValueChanged<bool> onLoud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final config =
        AppScope.of(context).notifications?.priorities ??
        const PriorityConfig();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 12),
        Text(
          'PRIORIDAD',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final p in ReminderPriority.values) ...[
              if (p != ReminderPriority.normal) const SizedBox(width: 6),
              Expanded(
                child: _PriorityButton(
                  key: Key('priority-${p.name}'),
                  label: p.label,
                  color: priorityColor(p),
                  selected: reminder.priority == p,
                  onTap: () => onPriority(p),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _explain(reminder.priority, config),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
          ),
        ),
        InkWell(
          key: const Key('priority-loud'),
          onTap: () => onLoud(!reminder.loud),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                height: 28,
                child: Checkbox(
                  value: reminder.loud,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => onLoud(v ?? false),
                ),
              ),
              const Icon(Icons.notifications_off_outlined, size: 16),
              const SizedBox(width: 4),
              Text(
                'Sonar aunque esté en silencio',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _explain(ReminderPriority p, PriorityConfig c) => switch (p) {
    ReminderPriority.normal => 'Avisa una vez, a la hora.',
    ReminderPriority.media =>
      'Repite cada ${c.mediaEvery} min '
          '${c.mediaInHours ? 'de ${c.mediaFrom} a ${c.mediaTo} h' : 'durante ${PriorityConfig.forLabel(c.mediaFor).toLowerCase()}'}'
          ', hasta "Hecho".',
    ReminderPriority.alta =>
      'Suena ${c.altaTimes} veces'
          '${c.altaVibrate ? ' y vibra' : ''}; repite cada ${c.altaEvery} min '
          'hasta "Hecho".',
  };
}

class _PriorityButton extends StatelessWidget {
  const _PriorityButton({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? color : scheme.outlineVariant,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? color : scheme.onSurface,
            ),
          ),
        ),
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
    this.footer,
  });

  final Reminder reminder;
  final bool active;
  final List<Widget> actions;
  final Widget? said;

  /// Debajo de los botones: la prioridad.
  final Widget? footer;

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
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (said != null) ...[said!, const SizedBox(height: 2)],
            TapToExpand(
              reminder.title,
              key: const Key('reminder-title'),
              maxLines: 2,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                decoration: active ? null : TextDecoration.lineThrough,
              ),
            ),
            // Cuándo y, a la derecha, "Activo" (en un renglón, para que
            // entre la tarjeta entera).
            Row(
              children: [
                Expanded(child: Text(describeSchedule(reminder))),
                const SizedBox(width: 6),
                Icon(
                  active ? Icons.check_circle : Icons.cancel,
                  color: active ? Colors.green : scheme.onSurfaceVariant,
                  size: 18,
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
            if (next != null) Text('Próximo: ${Fmt.when(next)}'),
            const SizedBox(height: 6),
            Row(children: actions),
            ?footer,
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
      items.add(
        ChatBubble(text: m.text, mine: m.mine, error: m.error, at: m.at),
      );
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

/// Botón grande para hablar y, debajo, un recuadro chico para escribir.
class _Composer extends StatelessWidget {
  const _Composer({
    this.compact = false,
    required this.input,
    required this.busy,
    required this.dictatingIntoField,
    required this.onTalk,
    required this.onFieldMic,
    required this.onSend,
  });

  /// Con un recordatorio a la vista, el micrófono un poco más chico.
  final bool compact;
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
          width: compact ? 52 : 64,
          height: compact ? 52 : 64,
          child: FloatingActionButton.large(
            heroTag: 'mic',
            tooltip: 'Hablar',
            backgroundColor: scheme.secondary,
            foregroundColor: scheme.onSecondary,
            onPressed: busy || dictatingIntoField ? null : onTalk,
            child: Icon(Icons.mic, size: compact ? 26 : 30),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Tocá para hablar',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: compact ? 11 : null,
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
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

/// Texto que, si no entra en [maxLines], termina en "…"; al tocarlo se ve
/// entero y al volver a tocarlo se cierra (pedido del usuario para los
/// mensajes largos, así la tarjeta del Chat entra siempre).
class TapToExpand extends StatefulWidget {
  const TapToExpand(this.text, {super.key, required this.maxLines, this.style});

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  State<TapToExpand> createState() => _TapToExpandState();
}

class _TapToExpandState extends State<TapToExpand> {
  bool _open = false;

  @override
  void didUpdateWidget(TapToExpand old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _open = false;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _open = !_open),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topLeft,
      child: Text(
        widget.text,
        maxLines: _open ? null : widget.maxLines,
        overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
        style: widget.style,
      ),
    ),
  );
}
