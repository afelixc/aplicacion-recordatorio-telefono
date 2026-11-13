import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/sheets.dart';
import '../chat/dictation.dart';
import 'note_input_bar.dart';
import 'notebook_page.dart';
import 'notes.dart';

/// La libreta chiquita que flota en Almanaque, Listado y Configuración, con
/// lo pendiente. Se puede arrastrar; al tocarla se anota rápido sin salir de
/// donde uno está (pedido del usuario).
class NotebookFab extends StatelessWidget {
  const NotebookFab({super.key, required this.settings, this.speech});

  final AppSettings settings;

  /// Para las pruebas.
  final Dictation? speech;

  static const libColor = Color(0xFFC98A00);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final night = Theme.of(context).brightness == Brightness.dark;
    final fg = night ? const Color(0xFFF0C04A) : libColor;
    return Material(
      color: Color.alphaBlend(libColor.withValues(alpha: 0.16), scheme.surface),
      elevation: 6,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: fg, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        key: const Key('notebook-fab'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => showQuickNote(context, settings, speech: speech),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.menu_book_outlined, color: fg, size: 22),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Libreta',
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        height: 1.1,
                      ),
                    ),
                    ToDoBadge(notebookToDo(settings.folders), size: 11),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja para anotar rápido: carpeta, tarea o nota, y el texto (escrito o
/// dictado). "Abrir libreta" lleva a la libreta completa.
Future<void> showQuickNote(
  BuildContext context,
  AppSettings settings, {
  Dictation? speech,
}) => showAppSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _QuickNote(settings: settings, speech: speech),
);

class _QuickNote extends StatefulWidget {
  const _QuickNote({required this.settings, this.speech});

  final AppSettings settings;
  final Dictation? speech;

  @override
  State<_QuickNote> createState() => _QuickNoteState();
}

class _QuickNoteState extends State<_QuickNote> {
  AppSettings get _s => widget.settings;
  late NoteFolder? _folder = _s.folders.isEmpty ? null : _s.folders.first;
  bool _memo = false;
  String? _done;

  Future<void> _save(String text) async {
    var f = _folder;
    if (f == null) {
      f = await _s.addFolder('General', folderColors.first);
      setState(() => _folder = f);
    }
    if (_memo) {
      await _s.saveMemo(f, null, Memo(text: text.trim(), at: DateTime.now()));
      setState(() => _done = 'Guardé la nota en ${f!.name}.');
    } else {
      final parts = splitNotes(text);
      if (parts.isEmpty) return;
      await _s.addNotes(f, parts);
      setState(
        () => _done = parts.length == 1
            ? 'Anoté 1 cosa en ${f!.name}.'
            : 'Anoté ${parts.length} cosas en ${f!.name}.',
      );
    }
  }

  Future<void> _newFolder() async {
    final r = await editFolder(context);
    if (r == null) return;
    final f = await _s.addFolder(r.$1, r.$2);
    setState(() => _folder = f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_outlined,
                      color: NotebookFab.libColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Anotar en la libreta',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('quick-open-notebook'),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Abrir libreta'),
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pop();
                        openNotebook(nav.context, _s);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // La carpeta donde se anota.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in _s.folders)
                      ChoiceChip(
                        label: Text(f.name),
                        avatar: Icon(
                          Icons.folder,
                          size: 16,
                          color: Color(f.color),
                        ),
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        selected: identical(f, _folder),
                        onSelected: (_) => setState(() => _folder = f),
                      ),
                    ActionChip(
                      key: const Key('quick-new-folder'),
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('Carpeta'),
                      visualDensity: VisualDensity.compact,
                      onPressed: _newFolder,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.check_box_outlined, size: 18),
                      label: Text('Tarea'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.sticky_note_2_outlined, size: 18),
                      label: Text('Nota'),
                    ),
                  ],
                  selected: {_memo},
                  onSelectionChanged: (v) => setState(() => _memo = v.first),
                ),
                if (_done != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '✓ $_done',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
          NoteInputBar(
            key: ValueKey(_memo),
            language: _s.language,
            speech: widget.speech,
            hint: _memo
                ? 'Escribí o dictá la nota…'
                : 'Escribí o dictá lo que tenés que hacer…',
            onSubmit: _save,
          ),
        ],
      ),
    );
  }
}
