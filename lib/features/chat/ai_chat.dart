import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../data/reminder.dart';
import '../../data/usage.dart';
import '../ai/ai_provider.dart';
import '../ai/ai_providers.dart';
import '../ai/pricing.dart';
import '../ai/reminder_interpreter.dart';
import '../reminders/reminder_form.dart';
import 'chat_screen.dart';

class _Message {
  const _Message(this.text, {this.mine = false, this.error = false});

  final String text;
  final bool mine;
  final bool error;
}

/// Chat con IA: el usuario escribe o habla, la IA arma el recordatorio y el
/// usuario lo confirma o lo corrige antes de guardarlo.
class AiChat extends StatefulWidget {
  const AiChat({super.key, required this.settings, this.interpreter});

  final AppSettings settings;

  /// Para las pruebas; si es null se arma con la configuración.
  final ReminderInterpreter? interpreter;

  @override
  State<AiChat> createState() => _AiChatState();
}

class _AiChatState extends State<AiChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  final _messages = <_Message>[
    const _Message(
      'Hola. Decime o escribime qué querés que te recuerde y cuándo. '
      'Por ejemplo: "Recordame el viernes a las 9 de la mañana lavar el auto".',
    ),
  ];

  Reminder? _pending;
  int _pendingVersion = 0;
  bool _thinking = false;
  bool _listening = false;

  /// Si la IA hizo una pregunta, el pedido anterior para no perder contexto.
  String? _previousRequest;

  static const _examples = [
    'Recordame el viernes a las 9 de la mañana lavar el auto',
    'Todos los lunes y jueves a las 19 ir al gimnasio',
    'Mañana a las 20 llamar a Juan',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _add(_Message m) {
    setState(() => _messages.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

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
    _add(_Message(text, mine: true));
    setState(() {
      _thinking = true;
      _pending = null;
    });

    final request = _previousRequest == null
        ? text
        : 'Pedido anterior: $_previousRequest\nRespuesta del usuario: $text';
    try {
      final interpreter = await _interpreter();
      final result = await interpreter.interpret(request);
      if (!mounted) return;
      _recordUsage(interpreter, result.usage);
      if (result.ok) {
        _previousRequest = null;
        _add(
          const _Message('Entendí esto. Revisalo y corregí lo que haga falta:'),
        );
        setState(() {
          _pending = result.reminder;
          _pendingVersion++;
        });
      } else {
        _previousRequest = request;
        _add(_Message(result.message));
      }
    } on AiException catch (e) {
      _add(_Message(e.message, error: true));
    } catch (_) {
      _add(
        const _Message(
          'No me pude conectar. Revisá tu internet, o cargalo a mano.',
          error: true,
        ),
      );
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
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

  Future<void> _confirm(Reminder r) async {
    await AppScope.of(context).reminders.save(r);
    setState(() => _pending = null);
    _add(_Message('Guardado ✓ "${r.title}", ${describeSchedule(r)}.'));
  }

  void _discard() {
    setState(() => _pending = null);
    _previousRequest = null;
    _add(const _Message('Listo, lo descarté.'));
  }

  void _manual() {
    final now = DateTime.now();
    setState(() {
      _pending = Reminder(
        title: '',
        dueAt: DateTime(now.year, now.month, now.day, now.hour + 1),
      );
      _pendingVersion++;
    });
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      _add(
        const _Message(
          'No pude usar el micrófono. Permití el acceso al micrófono para Recordame '
          'en los ajustes del teléfono, o escribilo.',
          error: true,
        ),
      );
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: widget.settings.language.replaceAll('-', '_'),
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        _input.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
          _send(result.recognizedWords);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = providerById(widget.settings.providerId);
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in _messages)
                ChatBubble(text: m.text, mine: m.mine, error: m.error),
              if (_thinking)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text('Pensando con ${provider.name}…'),
                    ],
                  ),
                ),
              if (_pending != null)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ReminderForm(
                      key: ValueKey(_pendingVersion),
                      initial: _pending,
                      submitLabel: 'Confirmar y guardar',
                      onCancel: _discard,
                      onSubmit: _confirm,
                    ),
                  ),
                ),
              if (_messages.length == 1 && _pending == null && !_thinking)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in _examples)
                      ActionChip(label: Text(e), onPressed: () => _send(e)),
                    ActionChip(
                      avatar: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Cargar a mano'),
                      onPressed: _manual,
                    ),
                  ],
                ),
            ],
          ),
        ),
        Material(
          color: scheme.surface,
          elevation: 3,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: FloatingActionButton.large(
                      heroTag: 'mic',
                      tooltip: _listening ? 'Dejar de escuchar' : 'Hablar',
                      backgroundColor: _listening
                          ? scheme.error
                          : scheme.secondary,
                      foregroundColor: _listening
                          ? scheme.onError
                          : scheme.onSecondary,
                      onPressed: _thinking ? null : _toggleMic,
                      child: Icon(
                        _listening ? Icons.stop : Icons.mic,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _listening ? 'Escuchando…' : 'Tocá para hablar',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('chat-input'),
                          controller: _input,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          decoration: const InputDecoration(
                            hintText:
                                'O escribilo: recordame el lunes a las 8…',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Enviar',
                        onPressed: _thinking ? null : () => _send(_input.text),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
