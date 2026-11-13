import 'package:flutter/material.dart';

import '../chat/dictation.dart';
import '../chat/talking_panel.dart';

/// Abajo de la libreta: campo para escribir con ✓ verde (Anotar) y el
/// micrófono al lado. Al dictar se usa el mismo panel que en el Chat
/// ("Grabando 0:12"): no se corta en las pausas y junta todo lo dicho.
class NoteInputBar extends StatefulWidget {
  const NoteInputBar({
    super.key,
    required this.language,
    required this.onSubmit,
    this.hint = 'Escribí o dictá cosas para anotar…',
    this.speech,
  });

  final String language;
  final ValueChanged<String> onSubmit;
  final String hint;

  /// Para las pruebas.
  final Dictation? speech;

  @override
  State<NoteInputBar> createState() => _NoteInputBarState();
}

class _NoteInputBarState extends State<NoteInputBar> {
  final _input = TextEditingController();
  late final Dictation _dictation = widget.speech ?? Dictation();

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_changed);
    _input.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dictation.removeListener(_changed);
    if (widget.speech == null) _dictation.dispose();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    widget.onSubmit(text);
  }

  Future<void> _talk() async {
    // Sin el teclado abierto, como en el Chat.
    FocusScope.of(context).unfocus();
    final ok = await _dictation.start(language: widget.language);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pude usar el micrófono. Permitilo en los ajustes del teléfono, '
            'o escribilo.',
          ),
        ),
      );
    }
  }

  Future<void> _done() async {
    final text = await _dictation.finish();
    if (text.trim().isNotEmpty) widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: _dictation.active
              ? TalkingPanel(
                  text: _dictation.text,
                  onCancel: _dictation.cancel,
                  onSend: _done,
                  sendLabel: 'Anotar',
                  hint:
                      'Hablá tranquilo, no se corta. Decí "uno…, dos…, tres…" '
                      'y cuando termines tocá Anotar.',
                )
              : Row(
                  // Campo, ✓ y micrófono del mismo alto y alineados.
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('notebook-input'),
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 14),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _RoundButton(
                      key: const Key('notebook-send'),
                      tooltip: 'Anotar',
                      icon: Icons.check,
                      color: Colors.green.shade600,
                      onPressed: _input.text.trim().isEmpty ? null : _send,
                    ),
                    const SizedBox(width: 6),
                    _RoundButton(
                      key: const Key('notebook-mic'),
                      tooltip: 'Dictar',
                      icon: Icons.mic,
                      color: scheme.secondary,
                      onPressed: _talk,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Botón redondo de 40, igual para ✓ y el micrófono.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 22,
    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: color.withValues(alpha: 0.35),
      disabledForegroundColor: Colors.white,
    ),
    icon: Icon(icon),
  );
}
