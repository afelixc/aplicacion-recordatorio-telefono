import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../chat/dictation.dart';
import '../reminders/reminder_editor.dart';
import 'notes.dart';

Future<void> openNotebook(BuildContext context, AppSettings settings) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NotebookPage(settings: settings)),
    );

/// Libreta: cosas para hacer, sin fecha ni aviso. Se dictan varias juntas
/// ("uno… dos… tres…"), cada una va a un renglón y se tachan al hacerlas.
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key, required this.settings, this.speech});

  final AppSettings settings;

  /// Para las pruebas.
  final Dictation? speech;

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  final _input = TextEditingController();
  late final Dictation _dictation = widget.speech ?? Dictation();
  final _fresh = <NoteItem>{};
  String? _message;

  AppSettings get _s => widget.settings;

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_onDictation);
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictation);
    if (widget.speech == null) _dictation.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onDictation() {
    if (_dictation.active) {
      _input.text = _dictation.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    setState(() {});
  }

  Future<void> _add(String text) async {
    final parts = splitNotes(text);
    _input.clear();
    if (parts.isEmpty) return;
    await _s.addNotes(parts);
    setState(() {
      _fresh
        ..clear()
        ..addAll(_s.notes.take(parts.length));
      _message = parts.length == 1
          ? 'Anoté 1 cosa en la libreta.'
          : 'Anoté ${parts.length} cosas en la libreta.';
    });
  }

  Future<void> _mic() async {
    if (_dictation.active) {
      await _add(await _dictation.finish());
      return;
    }
    final ok = await _dictation.start(
      language: _s.language,
      initialText: _input.text,
    );
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

  Future<void> _cancelDictation() async {
    await _dictation.cancel();
    _input.clear();
  }

  Future<void> _delete(NoteItem note) async {
    final index = _s.notes.indexOf(note);
    await _s.removeNote(note);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Borré "${note.text}".'),
          duration: const Duration(seconds: 5),
          persist: false,
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () => _s.insertNote(index, note),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = _dictation.active;
    return Scaffold(
      appBar: AppBar(title: const Text('Libreta')),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: _s,
              builder: (context, _) {
                final pending = [
                  for (final n in _s.notes)
                    if (!n.done) n,
                ];
                final done = [
                  for (final n in _s.notes)
                    if (n.done) n,
                ];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (_message != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('✓ $_message'),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      'Cosas para hacer, sin fecha ni aviso. Tocá el micrófono y '
                      'decí varias juntas: "uno… dos… tres…". Cada una va a un '
                      'renglón.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _Section('Para hacer (${pending.length})'),
                    _Paper(
                      children: pending.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  'No te falta nada.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ]
                          : [
                              for (final n in pending)
                                _NoteRow(
                                  note: n,
                                  fresh: _fresh.contains(n),
                                  onDone: (v) => _s.setNoteDone(n, v),
                                  trailing: IconButton(
                                    tooltip: 'Pasar a recordatorio',
                                    icon: const Icon(
                                      Icons.notifications_active_outlined,
                                    ),
                                    onPressed: () => showReminderEditor(
                                      context,
                                      initialTitle: n.text,
                                    ),
                                  ),
                                ),
                            ],
                    ),
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Section('Hechos (${done.length})'),
                      _Paper(
                        children: [
                          for (final n in done)
                            _NoteRow(
                              note: n,
                              onDone: (v) => _s.setNoteDone(n, v),
                              trailing: IconButton(
                                tooltip: 'Borrar',
                                icon: const Icon(Icons.close),
                                onPressed: () => _delete(n),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          Material(
            elevation: 3,
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (recording)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Escuchando… cuando termines tocá Listo.',
                              ),
                            ),
                            TextButton(
                              onPressed: _cancelDictation,
                              child: const Text('Cancelar'),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('notebook-input'),
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            readOnly: recording,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Escribí o dictá cosas para anotar…',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              isDense: true,
                              suffixIcon: recording
                                  ? null
                                  : IconButton(
                                      tooltip: 'Anotar',
                                      icon: const Icon(Icons.playlist_add),
                                      onPressed: () => _add(_input.text),
                                    ),
                            ),
                            onSubmitted: _add,
                          ),
                        ),
                        const SizedBox(width: 8),
                        recording
                            ? FilledButton.icon(
                                key: const Key('notebook-done'),
                                icon: const Icon(Icons.check),
                                label: const Text('Listo'),
                                onPressed: _mic,
                              )
                            : IconButton.filled(
                                key: const Key('notebook-mic'),
                                tooltip: 'Dictar',
                                iconSize: 28,
                                icon: const Icon(Icons.mic),
                                onPressed: _mic,
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// La hoja de libreta: fondo amarillito con renglones.
class _Paper extends StatelessWidget {
  const _Paper({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? const Color(0xFF4A4325) : const Color(0xFFECDFA6);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2718) : const Color(0xFFFFFBEA),
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: line),
            c,
          ],
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.onDone,
    required this.trailing,
    this.fresh = false,
  });

  final NoteItem note;
  final ValueChanged<bool> onDone;
  final Widget trailing;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: fresh ? scheme.secondary.withValues(alpha: 0.18) : null,
      child: Row(
        children: [
          Checkbox(value: note.done, onChanged: (v) => onDone(v ?? false)),
          Expanded(
            child: InkWell(
              onTap: () => onDone(!note.done),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  note.text,
                  style: TextStyle(
                    fontSize: 17,
                    decoration: note.done ? TextDecoration.lineThrough : null,
                    color: note.done ? scheme.onSurfaceVariant : null,
                  ),
                ),
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
