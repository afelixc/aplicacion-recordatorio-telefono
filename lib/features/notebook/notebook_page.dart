import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/palette.dart';
import '../../core/settings.dart';
import '../../data/reminder.dart';
import '../chat/dictation.dart';
import '../reminders/reminders_screen.dart' show matchesSearch;
import 'marquee_text.dart';
import 'note_input_bar.dart';
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

  Future<void> _open(NoteFolder f, {NoteItem? note, String? word}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FolderPage(
            settings: _s,
            folder: f,
            speech: widget.speech,
            highlight: note,
            highlightWord: word,
          ),
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
                  childAspectRatio: 1.35,
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
    // Cada coincidencia por separado: la nota o el ítem de adentro.
    final items = <(NoteFolder, NoteItem, String, bool, String)>[
      for (final f in _s.folders)
        for (final n in f.items) ...[
          if (matchesSearch(n.text, q)) (f, n, n.text, n.done, 'En ${f.name}'),
          for (final x in n.sub)
            if (matchesSearch(x.text, q))
              (f, n, x.text, x.done, 'En ${f.name} › ${n.text}'),
        ],
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
      for (final (f, n, text, done, where) in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            done ? Icons.check_box : Icons.check_box_outline_blank,
            color: Color(f.color),
          ),
          title: Text(
            text,
            style: done
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: Text(where),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(f, note: n, word: q),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1.15,
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

/// Adentro de una carpeta: las notas numeradas. Solo el cuadradito las da por
/// hechas; tocar el renglón lo marca y muestra subir, bajar, editar, aviso y
/// borrar. Una nota puede tener una lista adentro (las compras).
class FolderPage extends StatefulWidget {
  const FolderPage({
    super.key,
    required this.settings,
    required this.folder,
    this.speech,
    this.highlight,
    this.highlightWord,
  });

  final AppSettings settings;
  final NoteFolder folder;
  final Dictation? speech;

  /// Desde el buscador: la nota a mostrar (abierta y resaltada) y la palabra.
  final NoteItem? highlight;
  final String? highlightWord;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  final _fresh = <NoteItem>{};
  late NoteItem? _selected = widget.highlight;
  String? _message;
  final _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.highlight != null) {
      // Lleva la pantalla hasta la nota buscada.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _highlightKey.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(
            c,
            alignment: 0.3,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }
  }

  bool _isHit(String text) {
    final w = widget.highlightWord;
    return w != null && w.isNotEmpty && matchesSearch(text, w);
  }

  /// Avisa si quedan ítems sin tildar adentro de la nota.
  Future<bool> _confirmUnfinished(NoteItem n, String action) async {
    final left = n.sub.where((x) => !x.done).length;
    if (left == 0) return true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fijate: quedaron cosas por hacer'),
        content: Text(
          '"${n.text}" todavía tiene $left '
          '${left == 1 ? 'ítem sin tildar' : 'ítems sin tildar'}. '
          'Si tocás Aceptar la $action igual; con Cancelar queda como está.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('unfinished-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  AppSettings get _s => widget.settings;
  NoteFolder get _f => widget.folder;

  Future<void> _add(String text) async {
    final parts = splitNotes(text);
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

  Future<void> _delete(NoteItem n) async {
    if (!await _confirmUnfinished(n, 'borro')) return;
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

  Future<void> _edit(NoteItem n) async {
    setState(() => _selected = null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditPage(
          settings: _s,
          folder: _f,
          note: n,
          speech: widget.speech,
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
    // Cosas sin terminar: notas sin tildar e ítems de adentro sin tildar.
    final unfinished =
        _f.pending.length +
        _f.items.fold<int>(
          0,
          (sum, n) => sum + n.sub.where((x) => !x.done).length,
        );
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          unfinished > 0
              ? 'Fijate: tiene cosas sin terminar'
              : 'Borrar carpeta',
        ),
        content: Text(
          unfinished > 0
              ? 'La carpeta "${_f.name}" todavía tiene $unfinished '
                    '${unfinished == 1 ? 'cosa sin terminar' : 'cosas sin terminar'}. '
                    'Si tocás Aceptar se borra todo; con Cancelar queda como está.'
              : '¿Borrar la carpeta "${_f.name}" con todo lo que tiene adentro?',
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
            child: Text(unfinished > 0 ? 'Aceptar' : 'Borrar'),
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
    final subDone = n.sub.where((x) => x.done).length;
    final night = Theme.of(context).brightness == Brightness.dark;
    final colors = _s.colorsFor(night: night);
    final tint = softColor(n.done ? colors.noteDone : colors.notePending);
    return Material(
      key: identical(n, widget.highlight) ? _highlightKey : null,
      color: identical(n, widget.highlight) && _isHit(n.text)
          ? Colors.amber.withValues(alpha: 0.35)
          : selected
          ? scheme.primaryContainer.withValues(alpha: 0.6)
          : _fresh.contains(n) && !n.done
          ? scheme.secondary.withValues(alpha: 0.18)
          : tint.fill(night),
      child: InkWell(
        // Tocar el renglón solo lo marca: hecho, únicamente con el cuadradito.
        onTap: () => setState(() => _selected = selected ? null : n),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: SizedBox(
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
                  ),
                  Checkbox(
                    value: n.done,
                    onChanged: (v) async {
                      if (v == true &&
                          !await _confirmUnfinished(n, 'doy por hecha')) {
                        return;
                      }
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
                            n.sub.isEmpty
                                ? n.text
                                : '${n.text}  ($subDone/${n.sub.length})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: n.sub.isEmpty
                                  ? null
                                  : FontWeight.w600,
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
                  if (n.sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Icon(
                        selected ? Icons.expand_less : Icons.expand_more,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              // La lista de adentro se despliega al tocar la nota; cerrada,
              // la nota ocupa un renglón como las demás (con el 0/4).
              if (selected)
                for (final (i, x) in n.sub.indexed)
                  // Tocar el ítem no cierra la nota: solo el título la cierra.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.only(left: 64),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Checkbox(
                              visualDensity: VisualDensity.compact,
                              value: x.done,
                              // Tildar un ítem deja la nota abierta.
                              onChanged: (v) async {
                                final u = await _s.replaceNote(
                                  _f,
                                  n,
                                  n.copyWith(
                                    sub: [...n.sub]
                                      ..[i] = SubItem(x.text, done: v ?? false),
                                  ),
                                );
                                setState(() => _selected = u);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: _isHit(x.text)
                                  ? BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.45,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    )
                                  : null,
                              child: Text(
                                x.text,
                                style: TextStyle(
                                  decoration: x.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: x.done
                                      ? scheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (selected && n.sub.isNotEmpty) const SizedBox(height: 8),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 34),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!n.done) ...[
                        _Tool(
                          tooltip: 'Subir',
                          icon: Icons.arrow_upward,
                          color: Colors.blue.shade700,
                          onPressed: pos == 0
                              ? null
                              : () => _s.moveNote(_f, n, -1),
                        ),
                        _Tool(
                          tooltip: 'Bajar',
                          icon: Icons.arrow_downward,
                          color: Colors.blue.shade700,
                          onPressed: pos == list.length - 1
                              ? null
                              : () => _s.moveNote(_f, n, 1),
                        ),
                      ],
                      _Tool(
                        tooltip: 'Editar',
                        icon: Icons.edit,
                        color: Colors.green.shade700,
                        onPressed: () => _edit(n),
                      ),
                      if (!n.done)
                        _Tool(
                          tooltip: 'Avisarme',
                          icon: Icons.notifications_active,
                          color: Colors.amber.shade800,
                          onPressed: () => _alarm(n),
                        ),
                      _Tool(
                        tooltip: 'Borrar',
                        icon: Icons.delete,
                        color: Colors.red.shade700,
                        onPressed: () => _delete(n),
                      ),
                    ],
                  ),
                ),
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
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final color = Color(_f.color);
        final pending = _f.pending;
        final done = _f.done;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Icon(Icons.folder, color: color),
                const SizedBox(width: 8),
                Expanded(child: MarqueeText(_f.name)),
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
                      'Tocá un renglón para moverlo, editarlo (y armar una '
                      'lista adentro, como las compras), ponerle aviso o '
                      'borrarlo. Solo el cuadradito lo da por hecho.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              NoteInputBar(
                language: _s.language,
                speech: widget.speech,
                onSubmit: _add,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Botoncito de color con recuadro (subir, bajar, editar, aviso, borrar).
class _Tool extends StatelessWidget {
  const _Tool({
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: enabled ? 0.15 : 0.05),
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: 0.3),
        side: BorderSide(
          color: color.withValues(alpha: enabled ? 0.8 : 0.2),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon),
    );
  }
}

/// Botoncito de color más chico, para los ítems de adentro de una nota.
class _SmallTool extends StatelessWidget {
  const _SmallTool({
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
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 18,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: color.withValues(alpha: enabled ? 0.15 : 0.05),
          foregroundColor: color,
          disabledForegroundColor: color.withValues(alpha: 0.3),
          side: BorderSide(color: color.withValues(alpha: enabled ? 0.8 : 0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// Editar una nota: cambiar el texto y armar una lista adentro (pan, leche…),
/// escribiendo o dictando varias cosas juntas.
class NoteEditPage extends StatefulWidget {
  const NoteEditPage({
    super.key,
    required this.settings,
    required this.folder,
    required this.note,
    this.speech,
  });

  final AppSettings settings;
  final NoteFolder folder;
  final NoteItem note;
  final Dictation? speech;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late NoteItem _note = widget.note;
  late final _title = TextEditingController(text: widget.note.text);

  AppSettings get _s => widget.settings;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save(NoteItem updated) async {
    final saved = await _s.replaceNote(widget.folder, _note, updated);
    setState(() => _note = saved);
  }

  Future<void> _moveSub(int i, int dir) {
    final sub = [..._note.sub];
    final x = sub[i];
    sub[i] = sub[i + dir];
    sub[i + dir] = x;
    return _save(_note.copyWith(sub: sub));
  }

  Future<void> _editSub(int i) async {
    final x = _note.sub[i];
    final c = TextEditingController(text: x.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar'),
        content: TextField(
          key: const Key('sub-edit'),
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('sub-edit-save'),
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final t = text?.trim() ?? '';
    if (t.isEmpty || t == x.text) return;
    await _save(
      _note.copyWith(sub: [..._note.sub]..[i] = SubItem(t, done: x.done)),
    );
  }

  Future<void> _saveTitle() async {
    final t = _title.text.trim();
    if (t.isEmpty || t == _note.text) return;
    await _save(_note.copyWith(text: t));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _saveTitle(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Editar nota')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  TextField(
                    key: const Key('note-title'),
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nota',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _saveTitle(),
                    onTapOutside: (_) => _saveTitle(),
                  ),
                  const SizedBox(height: 18),
                  _Section('Lista adentro de la nota (${_note.sub.length})'),
                  if (_note.sub.isEmpty)
                    Text(
                      'Por ejemplo, para ir de compras: escribí o dictá abajo '
                      '"pan, leche, huevos" o "uno pan dos leche tres '
                      'huevos". Cada cosa queda en su renglón.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    _Paper(
                      color: Color(widget.folder.color),
                      children: [
                        for (final (i, x) in _note.sub.indexed)
                          Row(
                            children: [
                              Checkbox(
                                value: x.done,
                                onChanged: (v) => _save(
                                  _note.copyWith(
                                    sub: [..._note.sub]
                                      ..[i] = SubItem(x.text, done: v ?? false),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  x.text,
                                  style: TextStyle(
                                    fontSize: 16,
                                    decoration: x.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              _SmallTool(
                                tooltip: 'Subir',
                                icon: Icons.arrow_upward,
                                color: Colors.blue.shade700,
                                onPressed: i == 0
                                    ? null
                                    : () => _moveSub(i, -1),
                              ),
                              _SmallTool(
                                tooltip: 'Bajar',
                                icon: Icons.arrow_downward,
                                color: Colors.blue.shade700,
                                onPressed: i == _note.sub.length - 1
                                    ? null
                                    : () => _moveSub(i, 1),
                              ),
                              _SmallTool(
                                tooltip: 'Editar',
                                icon: Icons.edit,
                                color: Colors.green.shade700,
                                onPressed: () => _editSub(i),
                              ),
                              _SmallTool(
                                tooltip: 'Quitar',
                                icon: Icons.close,
                                color: Colors.red.shade700,
                                onPressed: () => _save(
                                  _note.copyWith(
                                    sub: [..._note.sub]..removeAt(i),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
            NoteInputBar(
              language: _s.language,
              speech: widget.speech,
              hint: 'Agregá ítems a la lista…',
              onSubmit: (text) => _save(
                _note.copyWith(
                  sub: [
                    ..._note.sub,
                    for (final t in splitNotes(text)) SubItem(t),
                  ],
                ),
              ),
            ),
          ],
        ),
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
