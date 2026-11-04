import 'dart:async';

import 'package:flutter/material.dart';

/// Mientras se habla: como grabar un audio. Se ve que está grabando y el
/// tiempo; lo que se va entendiendo queda escondido (se puede ver si se quiere).
class TalkingPanel extends StatefulWidget {
  const TalkingPanel({
    super.key,
    required this.text,
    required this.onCancel,
    required this.onSend,
    this.sendLabel = 'Enviar',
    this.hint = 'Hablá tranquilo, no se corta. Cuando termines tocá Enviar.',
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final String sendLabel;
  final String hint;

  @override
  State<TalkingPanel> createState() => _TalkingPanelState();
}

class _TalkingPanelState extends State<TalkingPanel> {
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
          widget.hint,
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
                label: Text(widget.sendLabel),
                onPressed: widget.onSend,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
