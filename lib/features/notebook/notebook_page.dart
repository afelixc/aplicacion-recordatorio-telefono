import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../data/reminder.dart';
import '../chat/dictation.dart';
import '../reminders/reminders_screen.dart' show matchesSearch;
import 'notes.dart';

Future<void> openNotebook(BuildContext context, AppSettings settings) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NotebookPage(settings: settings)),
    );

/// Libreta: carpetas (Impresora, Auto…) con cosas para hacer. Arriba, un
/// buscador que busca en los nombres de las carpetas y en lo anotado.
class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key, required this.settings, this.speech});

  final AppSettings settings;

  /// Para las pruebas.
  final Dictation? speech;

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  final _search = TextEditingController();

  AppSettings get _s => widget.settings;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(NoteFolder f) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          FolderPage(settings: _s, folder: f, speech: widget.speech),
    ),
  );

  Future<void> _newFolder() async {
    final r = await editFolder(context);
    if (r == null) return;
    final f = await _s.addFolder(r.$1, r.$2);
    if (mounted) await _open(f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Libreta')),
      body: ListenableBuilder(
        listenable: Listenable.merge([_s, _search]),
        builder: (context, _) {
          final q = _search.text.trim();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              TextField(
                key: const Key('notebook-search'),
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Buscar en la libreta…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar búsqueda',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _search.clear,
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (q.isNotEmpty)
                ..._results(q, theme)
              else ...[
                Text(
                  'Tus carpetas. Tocá una para ver lo que tenés para hacer.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.6,
                  children: [
                    for (final f in _s.folders)
                      _FolderCard(folder: f, onTap: () => _open(f)),
                  ],
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('new-folder'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Nueva carpeta'),
                  onPressed: _newFolder,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _results(String q, ThemeData theme) {
    final folders = [
      for (final f in _s.folders)
        if (matchesSearch(f.name, q)) f,
    ];
    final items = [
      for (final f in _s.folders)
        for (final n in f.items)
          if (matchesSearch(n.text, q)) (f, n),
    ];
    if (folders.isEmpty && items.isEmpty) {
      return [Text('No encontré "$q" en la libreta.')];
    }
    return [
      for (final f in folders)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.folder, color: Color(f.color)),
          title: Text(f.name),
          subtitle: const Text('Carpeta'),
          onTap: () => _open(f),
        ),
      for (final (f, n) in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            n.done ? Icons.check_box : Icons.check_box_outline_blank,
            color: Color(f.color),
          ),
          title: Text(
            n.text,
            style: n.done
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: Text('En ${f.name}'),
          onTap: () => _open(f),
        ),
    ];
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.folder, required this.onTap});

  final NoteFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.color);
    final pending = folder.pending.length;
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder, color: color),
              const SizedBox(height: 4),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                pending == 0 ? 'Todo hecho ✓' : '$pending para hacer',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nombre y color de una carpeta (nueva o para editar). Devuelve null si se
/// canceló.
Future<(String, int)?> editFolder(BuildContext context, {NoteFolder? folder}) {
  final name = TextEditingController(text: folder?.name ?? '');
  var color = folder?.color ?? folderColors.first;
  return showModalBottomSheet<(String, int)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        void ok() {
          final n = name.text.trim();
          if (n.isEmpty) return;
          Navigator.pop(context, (n[0].toUpperCase() + n.substring(1), color));
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                folder == null ? 'Nueva carpeta' : 'Editar carpeta',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('folder-name'),
                controller: name,
                autofocus: folder == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Impresora, Auto…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => ok(),
              ),
              const SizedBox(height: 14),
              const Text('Color'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in folderColors)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setSheet(() => color = c),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(c),
                        child: c == color
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('folder-save'),
                      onPressed: ok,
                      child: Text(folder == null ? 'Crear' : 'Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Adentro de una carpeta: las cosas numeradas. Solo el cuadradito las da por
/// hechas; tocar el renglón lo marca y muestra subir, bajar, aviso y borrar.
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.settings,
    required this.folder,
    this.speech,
  });

  final AppSettings settings;
  final NoteFolder folder;
  final Dictation? speech;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  final _input = TextEditingController();
  late final Dictation _dictation = widget.speech ?? Dictation();
  final _fresh = <NoteItem>{};
  NoteItem? _selected;
  String? _message;

  AppSettings get _s => widget.settings;
  NoteFolder get _f => widget.folder;

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_onDictation);
    _input.addListener(() => setState(() {}));
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
    final added = await _s.addNotes(_f, parts);
    setState(() {
      _selected = null;
      _fresh
        ..clear()
        ..addAll(added);
      _message = parts.length == 1
          ? 'Anoté 1 cosa en ${_f.name}.'
          : 'Anoté ${parts.length} cosas en ${_f.name}.';
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

  Future<void> _delete(NoteItem n) async {
    final index = await _s.removeNote(_f, n);
    setState(() => _selected = null);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Borré "${n.text}".'),
          duration: const Duration(seconds: 5),
          persist: false,
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () => _s.insertNote(_f, index, n),
          ),
        ),
      );
  }

  /// La campanita: pide día y hora y arma un recordatorio que suena.
  Future<void> _alarm(NoteItem n) async {
    final repo = AppScope.of(context).reminders;
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final day = await showDatePicker(
      context: context,
      helpText: '¿Qué día te aviso?',
      initialDate: n.alarm ?? tomorrow,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      helpText: '¿A qué hora?',
      initialTime: n.alarm == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(n.alarm!),
    );
    if (time == null) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final r = await repo.save(
      Reminder(title: 'Libreta · ${_f.name}: ${n.text}', dueAt: at),
    );
    await _s.setNoteAlarm(_f, n, at);
    setState(() => _selected = null);
    messenger.showSnackBar(
      SnackBar(content: Text('Te aviso: ${describeSchedule(r)}.')),
    );
  }

  Future<void> _editFolder() async {
    final r = await editFolder(context, folder: _f);
    if (r == null) return;
    _f
      ..name = r.$1
      ..color = r.$2;
    await _s.saveNotes();
  }

  Future<void> _deleteFolder() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar carpeta'),
        content: Text(
          '¿Borrar la carpeta "${_f.name}" con todo lo que tiene adentro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('folder-delete-yes'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final navigator = Navigator.of(context);
    await _s.deleteFolder(_f);
    navigator.pop();
  }

  Widget _row(NoteItem n, int number, List<NoteItem> list) {
    final scheme = Theme.of(context).colorScheme;
    final selected = identical(_selected, n);
    final pos = list.indexOf(n);
    return Material(
      color: selected
          ? scheme.primaryContainer
          : _fresh.contains(n) && !n.done
          ? scheme.secondary.withValues(alpha: 0.18)
          : Colors.transparent,
      child: InkWell(
        // Tocar el renglón solo lo marca: hecho, únicamente con el cuadradito.
        onTap: () => setState(() => _selected = selected ? null : n),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$number.',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Checkbox(
                value: n.done,
                onChanged: (v) async {
                  await _s.setNoteDone(_f, n, v ?? false);
                  setState(() => _selected = null);
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.text,
                        style: TextStyle(
                          fontSize: 16,
                          decoration: n.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: n.done ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      if (n.alarm != null)
                        Text(
                          '🔔 ${Fmt.when(n.alarm!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (selected) ...[
                if (!n.done) ...[
                  IconButton(
                    tooltip: 'Subir',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: pos == 0 ? null : () => _s.moveNote(_f, n, -1),
                  ),
                  IconButton(
                    tooltip: 'Bajar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: pos == list.length - 1
                        ? null
                        : () => _s.moveNote(_f, n, 1),
                  ),
                  IconButton(
                    tooltip: 'Avisarme',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.notifications_active_outlined),
                    onPressed: () => _alarm(n),
                  ),
                ],
                IconButton(
                  tooltip: 'Borrar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(n),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = _dictation.active;
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final color = Color(_f.color);
        final pending = _f.pending;
        final done = _f.done;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(Icons.folder, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(_f.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('folder-edit'),
                tooltip: 'Cambiar nombre y color',
                icon: const Icon(Icons.edit_outlined),
                onPressed: _editFolder,
              ),
              IconButton(
                key: const Key('folder-delete'),
                tooltip: 'Borrar carpeta',
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteFolder,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
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
                    _Section('Para hacer (${pending.length})'),
                    _Paper(
                      color: color,
                      children: pending.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  'No falta nada en esta carpeta. Escribí '
                                  'abajo o tocá el micrófono.',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ]
                          : [
                              for (final (i, n) in pending.indexed)
                                _row(n, i + 1, pending),
                            ],
                    ),
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Section('Hechos (${done.length})'),
                      _Paper(
                        color: color,
                        children: [
                          for (final (i, n) in done.indexed)
                            _row(n, i + 1, done),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Tocá un renglón para moverlo, ponerle aviso o '
                      'borrarlo. Solo el cuadradito lo da por hecho.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                      children: [
                        if (recording)
                          Row(
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
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('notebook-input'),
                                controller: _input,
                                minLines: 1,
                                maxLines: 4,
                                readOnly: recording,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText:
                                      'Escribí o dictá cosas para anotar…',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  isDense: true,
                                  suffixIcon: recording
                                      ? null
                                      : Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: IconButton.filled(
                                            key: const Key('notebook-send'),
                                            tooltip: 'Anotar',
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                            ),
                                            icon: const Icon(Icons.check),
                                            onPressed:
                                                _input.text.trim().isEmpty
                                                ? null
                                                : () => _add(_input.text),
                                          ),
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
      },
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

/// La hoja: fondo suave del color de la carpeta, con renglones.
class _Paper extends StatelessWidget {
  const _Paper({required this.color, required this.children});

  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = color.withValues(alpha: 0.35);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
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
