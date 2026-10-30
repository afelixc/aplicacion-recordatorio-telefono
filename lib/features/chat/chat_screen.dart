import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../reminders/reminder_form.dart';

/// Pestaña principal. Por ahora solo el modo gratis: carga manual con formulario.
/// En las etapas 6 y 7 se suma el chat con IA y la grabación de voz.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
        _Bubble(
          text:
              'Hola. Cargá qué querés que te recuerde y cuándo. '
              'Más adelante vas a poder escribirlo o decirlo de corrido y la IA lo arma sola.',
        ),
        if (_lastSaved != null) _Bubble(text: _lastSaved!),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, right: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: Text(text),
      ),
    );
  }
}
