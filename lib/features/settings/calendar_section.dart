import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../core/sheets.dart';
import '../../data/reminder.dart';
import '../calendar_sync/calendar_sync.dart';
import '../calendar_sync/device_calendar.dart';
import '../calendar_sync/ical.dart';
import 'battery_help.dart';
import 'calendar_check_page.dart';
import 'settings_screen.dart';

/// Configuración → Google Calendar: usa el calendario que ya está en el
/// teléfono, en un sentido, en el otro o en los dos.
class CalendarSection extends StatefulWidget {
  const CalendarSection({super.key, required this.sync});

  final CalendarSync sync;

  @override
  State<CalendarSection> createState() => _CalendarSectionState();
}

enum _Send { all, onlyNew }

class _CalendarSectionState extends State<CalendarSection> {
  bool? _permission;
  List<PhoneCalendar>? _calendars;
  String? _loadError;

  static const _periods = [
    ('30 días', Duration(days: 30)),
    ('6 meses', Duration(days: 182)),
    ('1 año', Duration(days: 365)),
    ('Todo', Duration(days: 3650)),
  ];
  int _period = 0;
  List<CalendarEvent>? _events;
  final _checked = <String>{};
  bool _busy = false;

  AppSettings get _settings => widget.sync.settings;
  DeviceCalendar get _cal => widget.sync.calendar;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_changed);
    _start();
  }

  @override
  void dispose() {
    _settings.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final ok = await _cal.hasPermission();
    if (!mounted) return;
    setState(() => _permission = ok);
    if (ok) await _loadCalendars();
  }

  Future<void> _askPermission() async {
    final ok = await _cal.requestPermission();
    if (!mounted) return;
    setState(() => _permission = ok);
    if (ok) {
      await _loadCalendars();
    } else {
      _say(
        'Sin el permiso no puedo usar el calendario. Si no te aparece el '
        'cartel, dalo en Ajustes del teléfono → Apps → Recordame → Permisos.',
      );
    }
  }

  Future<void> _loadCalendars() async {
    try {
      final list = await _cal.calendars();
      if (!mounted) return;
      setState(() => _calendars = list);
      final current = list.where((c) => c.id == _settings.calendarId);
      if (current.isEmpty && list.isNotEmpty) {
        final pick = list.firstWhere(
          (c) => c.primary && c.writable,
          orElse: () =>
              list.firstWhere((c) => c.writable, orElse: () => list.first),
        );
        await _settings.setCalendar(pick.id, pick.label);
      }
      await _loadEvents();
    } catch (_) {
      if (mounted) setState(() => _loadError = 'No pude leer tus calendarios.');
    }
  }

  Future<void> _loadEvents() async {
    if (_settings.calendarId == null) return;
    setState(() => _events = null);
    try {
      final events = await widget.sync.upcoming(_periods[_period].$2);
      if (!mounted) return;
      setState(() {
        _events = events;
        _checked.removeWhere((id) => !events.any((e) => _key(e) == id));
      });
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    }
  }

  /// Un evento que se repite aparece varias veces con el mismo id.
  static String _key(CalendarEvent e) =>
      '${e.id}@${e.start.millisecondsSinceEpoch}';

  void _say(String text, {int seconds = 5}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: Duration(seconds: seconds),
          persist: false,
        ),
      );
  }

  Future<void> _toggleSend(bool on) async {
    if (!on) {
      await _settings.setCalendarSend(false);
      return;
    }
    final repo = AppScope.of(context).reminders;
    final pending = (await repo.watchAll().first)
        .where((r) => !r.done && r.calendarEventId == null)
        .length;
    if (!mounted) return;
    final name = _settings.calendarName ?? 'tu calendario';
    final choice = await showDialog<_Send>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar al calendario'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Desde ahora, lo que cargues en Recordame '),
              const TextSpan(text: 'va a aparecer en:\n'),
              TextSpan(
                text: name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (pending > 0)
                TextSpan(
                  text:
                      '\n\nYa tenés $pending recordatorios pendientes cargados '
                      'de antes. ¿Qué hago con esos?',
                ),
            ],
          ),
        ),
        actions: [
          if (pending > 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _Send.all),
                child: Text('Mandar también esos $pending'),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: pending > 0
                ? OutlinedButton(
                    onPressed: () => Navigator.pop(context, _Send.onlyNew),
                    child: const Text(
                      'Esos no, solo lo que cargue desde ahora',
                      textAlign: TextAlign.center,
                    ),
                  )
                : FilledButton(
                    onPressed: () => Navigator.pop(context, _Send.onlyNew),
                    child: const Text('Sí, enviar'),
                  ),
          ),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar (no enviar nada)'),
            ),
          ),
        ],
      ),
    );
    if (choice == null) {
      if (mounted) _say('No se envió nada. Queda apagado.');
      return;
    }
    await _settings.setCalendarSend(true);
    if (choice == _Send.all) {
      setState(() => _busy = true);
      final sent = await widget.sync.sendExisting(repo);
      if (!mounted) return;
      setState(() => _busy = false);
      _say('Listo ✓ Mandé $sent recordatorios al calendario.');
      await _loadEvents();
    } else if (mounted) {
      _say('Listo ✓ Desde ahora, lo nuevo va al calendario.');
    }
  }

  // --- 5 · Link privado de Google ---

  Future<void> _pasteLink() async {
    final field = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pegá el link privado'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'En la computadora:\n'
                '1. Entrá a calendar.google.com\n'
                '2. Arriba a la derecha, ⚙ → Configuración\n'
                '3. A la izquierda, en "Configuración de mis calendarios", '
                'tocá tu calendario\n'
                '4. Bajá hasta "Integrar el calendario"\n'
                '5. Copiá la "Dirección secreta en formato iCal" (termina '
                'en .ics)\n'
                '6. Mandátela por WhatsApp o mail y pegala acá.',
              ),
              const SizedBox(height: 8),
              Text(
                'No se la pases a nadie: con ese link se puede ver tu '
                'calendario.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ical-field'),
                controller: field,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Link privado (.ics)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('ical-ok'),
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
    if (raw == null || !mounted) return;
    final url = cleanIcalUrl(raw);
    if (url == null) {
      _say(
        'Eso no parece el link del calendario. Tiene que empezar con '
        'https:// y terminar en .ics.',
        seconds: 8,
      );
      return;
    }
    setState(() => _busy = true);
    final now = DateTime.now();
    List<CalendarEvent> events;
    try {
      events = await widget.sync.icalReader(
        url,
        now,
        now.add(CalendarSync.autoWindow),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _say('$e', seconds: 8);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final repo = AppScope.of(context).reminders;
    final have = await repo.watchAll().first;
    if (!mounted) return;
    final missing = [
      for (final e in events)
        if (!alreadyHave(e, have)) e,
    ];
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.link, color: Colors.green),
        title: const Text('¡Funciona!'),
        content: Text(
          events.isEmpty
              ? 'Leí tu calendario desde Google, pero no hay nada anotado '
                    'para el próximo año. Lo que anotes de ahora en más va a '
                    'llegar a Recordame.'
              : 'Leí tu calendario desde Google: hay ${events.length} '
                    '${events.length == 1 ? 'evento' : 'eventos'} de acá a '
                    'un año (por ejemplo "${events.first.title}", '
                    '${Fmt.when(events.first.start)}).\n\n'
                    '¿Traigo a Recordame lo que ya está, o solo lo nuevo que '
                    'anotes de ahora en más?',
        ),
        actions: [
          if (missing.isNotEmpty)
            FilledButton(
              key: const Key('ical-all'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                missing.length == 1
                    ? 'Traer el que falta'
                    : 'Traer los ${missing.length} que faltan',
              ),
            ),
          TextButton(
            key: const Key('ical-new'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Solo lo nuevo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == false) {
      await _settings.addCalendarKnown(events.map((e) => e.id));
    }
    await _settings.setIcalUrl(url);
    await widget.sync.ensureBackground();
    final added = await widget.sync.autoImport(repo);
    if (!mounted) return;
    _say(
      added == 0
          ? 'Listo: lo nuevo de tu calendario va a llegar solo.'
          : 'Listo: traje $added. Lo nuevo va a llegar solo.',
      seconds: 6,
    );
  }

  Future<void> _readLinkNow() async {
    setState(() => _busy = true);
    try {
      await widget.sync.icalUpcoming(CalendarSync.autoWindow);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _say('$e', seconds: 8);
      }
      return;
    }
    if (!mounted) return;
    final added = await widget.sync.autoImport(AppScope.of(context).reminders);
    if (!mounted) return;
    setState(() => _busy = false);
    final name = lastIcalName ?? 'tu calendario';
    _say(
      'Leí "$name" ($lastIcalTotal en total). '
      '${added == 0
          ? 'No había nada nuevo: si falta algo, tocá "¿Qué ve el teléfono?".'
          : added == 1
          ? 'Traje 1 nuevo.'
          : 'Traje $added nuevos.'}',
      seconds: 8,
    );
  }

  Future<void> _removeLink() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Quitar el link?'),
        content: const Text(
          'Recordame deja de leer tu calendario desde Google. Lo que ya '
          'trajo queda como está.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('ical-remove-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _settings.setIcalUrl(null);
    await widget.sync.ensureBackground();
  }

  Future<void> _toggleAuto(bool on) async {
    if (on) {
      final name = _settings.calendarName ?? 'tu calendario';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.sync),
          title: Text('¿Traer lo nuevo de "$name"?'),
          content: const Text(
            'Desde ahora, lo que se anote en ese calendario te va a llegar a '
            'Recordame, aunque la app esté cerrada.\n\nLo que ya está no lo '
            'traigo (para eso usá el 3).',
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('cal-auto-yes'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sí, traer lo nuevo'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      );
      if (ok != true) {
        if (mounted) _say('No se trae nada. Queda apagado.');
        return;
      }
      await widget.sync.startAuto();
      if (mounted) {
        _say(
          'Listo ✓ Lo nuevo que anotes en el calendario va a llegar a Recordame.',
        );
      }
    } else {
      await widget.sync.stopAuto();
    }
  }

  Future<void> _add(List<Reminder> have) async {
    final repo = AppScope.of(context).reminders;
    final chosen = [
      for (final e in _events ?? const <CalendarEvent>[])
        if (_checked.contains(_key(e)) && !alreadyHave(e, have)) e,
    ];
    setState(() => _busy = true);
    final added = await widget.sync.import(chosen, repo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _checked.clear();
    });
    _say('Listo ✓ Agregué $added a Recordame. Te aviso a la hora de cada uno.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = _settings;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    if (_permission == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permission == false) {
      return SettingsCard(
        title: 'Permiso de calendario',
        children: [
          const Text(
            'Para usar tu Google Calendar, Recordame necesita permiso para '
            'ver y anotar en los calendarios del teléfono. Se usa el '
            'calendario que ya tenés: no se crea ninguno nuevo.',
          ),
          FilledButton.icon(
            key: const Key('cal-permission'),
            icon: const Icon(Icons.calendar_month),
            label: const Text('Dar permiso'),
            onPressed: _askPermission,
          ),
        ],
      );
    }

    final calendars = _calendars;
    final current = calendars?.where((c) => c.id == s.calendarId);
    final writable = current == null || current.isEmpty
        ? true
        : current.first.writable;
    final both = s.calendarSend && writable && s.calendarAuto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        _Box(
          color: Colors.green.shade800,
          background: Colors.green.shade50,
          text:
              'Permiso de calendario ✓ · Recordame puede ver y anotar en '
              'tus calendarios',
        ),
        SettingsCard(
          title: '1 · ¿Qué calendario uso?',
          children: [
            if (_loadError != null)
              Text(_loadError!, style: TextStyle(color: scheme.error))
            else if (calendars == null)
              const LinearProgressIndicator()
            else if (calendars.isEmpty)
              const Text(
                'No encontré calendarios en el teléfono. Fijate que tu cuenta '
                'de Google tenga Calendar activado.',
              )
            else
              _CalendarPicker(
                calendars: calendars,
                selected: s.calendarId,
                onPick: (c) async {
                  final turnedOff = await widget.sync.choose(c);
                  if (turnedOff && mounted) {
                    _say(
                      'Cambiaste a ${c.label}. Por seguridad apagué el envío '
                      '(2) y la traída automática (4). Si es el correcto, '
                      'prendelos de nuevo.',
                      seconds: 8,
                    );
                  }
                  await _loadEvents();
                },
              ),
            Text(
              'Se usa el que ya tenés: no se crea ningún calendario nuevo.',
              style: hint,
            ),
          ],
        ),
        SettingsCard(
          title: '2 · De Recordame → al calendario',
          children: [
            SwitchListTile(
              dense: true,
              key: const Key('cal-send'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar mis recordatorios al calendario'),
              subtitle: Text(
                !writable
                    ? 'Este calendario es solo para ver: no deja anotar. '
                          'Podés traer de él (3 y 4), pero para enviar elegí '
                          'otro en el 1.'
                    : s.calendarSend
                    ? 'Prendido: lo que cargás, cambiás o borrás en Recordame '
                          'aparece en ${s.calendarName ?? 'tu calendario'}.'
                    : 'Apagado: el calendario no se toca.',
              ),
              value: s.calendarSend && writable,
              onChanged: s.calendarId == null || _busy || !writable
                  ? null
                  : _toggleSend,
            ),
          ],
        ),
        SettingsCard(
          title: '3 · Traer del calendario',
          children: [
            Text(
              'Elegí cuánto querés ver, marcá lo que necesita aviso y confirmá.',
              style: hint,
            ),
            Row(
              spacing: 6,
              children: [
                for (final (i, (label, _)) in _periods.indexed)
                  Expanded(
                    child: ChoiceChip(
                      label: SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label),
                        ),
                      ),
                      labelPadding: EdgeInsets.zero,
                      showCheckmark: false,
                      selected: _period == i,
                      onSelected: (_) {
                        setState(() => _period = i);
                        _loadEvents();
                      },
                    ),
                  ),
              ],
            ),
            StreamBuilder<List<Reminder>>(
              stream: AppScope.of(context).reminders.watchAll(),
              builder: (context, snap) =>
                  _eventList(context, snap.data ?? const []),
            ),
          ],
        ),
        SettingsCard(
          title: '4 · Del calendario → a Recordame, siempre',
          children: [
            SwitchListTile(
              dense: true,
              key: const Key('cal-auto'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Traer lo nuevo automáticamente'),
              subtitle: Text(
                s.calendarAuto
                    ? 'Prendido: lo nuevo que anotes en '
                          '${s.calendarName ?? 'tu calendario'}, aunque sea '
                          'desde la compu, aparece en Recordame y te avisa, '
                          'aunque la app esté cerrada.'
                    : 'Apagado: solo se trae lo que elijas arriba.',
              ),
              value: s.calendarAuto,
              onChanged: s.calendarId == null ? null : _toggleAuto,
            ),
            if (both)
              _Box(
                color: Colors.green.shade800,
                background: Colors.green.shade50,
                text:
                    '⇄ Con el 2 y el 4 prendidos queda sincronizado en los '
                    'dos sentidos.',
              ),
            if (s.calendarAuto) const _BatteryHint(),
            if (s.calendarAuto)
              const _Box(
                color: Color(0xFF6B5418),
                background: Color(0xFFFFF4D6),
                text:
                    'Lo que viene del calendario te puede sonar dos veces: '
                    'Google Calendar también avisa. Si te molesta, apagá los '
                    'avisos de Google Calendar en el teléfono.',
              ),
          ],
        ),
        SettingsCard(
          title: '5 · Link privado de Google (si no llega nada)',
          children: [
            if (s.icalUrl == null) ...[
              Text(
                'Si lo que anotás en Google Calendar no llega al teléfono, '
                'Recordame lo puede leer directo de Google con el link '
                'privado de tu calendario. Solo lee: no anota nada en Google.',
                style: hint,
              ),
              FilledButton.icon(
                key: const Key('ical-paste'),
                icon: const Icon(Icons.link),
                label: const Text('Pegar el link privado'),
                onPressed: _busy ? null : _pasteLink,
              ),
            ] else ...[
              _Box(
                color: Colors.green.shade800,
                background: Colors.green.shade50,
                text:
                    'Conectado ✓ · Se lee de Google al abrir la app y cada '
                    '15 minutos.',
              ),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: _LinkButton(
                      key: const Key('ical-read'),
                      icon: Icons.refresh,
                      label: 'Leer ahora',
                      onPressed: _busy ? null : _readLinkNow,
                    ),
                  ),
                  Expanded(
                    child: _LinkButton(
                      key: const Key('ical-remove'),
                      icon: Icons.link_off,
                      label: 'Quitar link',
                      onPressed: _busy ? null : _removeLink,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        // Para ver por qué algo de Google Calendar no llegó.
        OutlinedButton.icon(
          key: const Key('cal-check'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('¿Qué ve el teléfono? (revisar)'),
          onPressed: s.calendarId == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CalendarCheckPage(sync: widget.sync),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Para el segundo paso: qué pasa en el calendario cuando marcás '
            'algo como hecho en Recordame (por ahora no se toca).',
            style: hint,
          ),
        ),
      ],
    );
  }

  Widget _eventList(BuildContext context, List<Reminder> have) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final events = _events;
    if (events == null) return const LinearProgressIndicator();
    final free = [
      for (final e in events)
        if (!alreadyHave(e, have)) e,
    ];
    final selected = free.where((e) => _checked.contains(_key(e))).length;
    final allOn = free.isNotEmpty && selected == free.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${events.length} en el calendario · $selected marcados',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (free.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  if (allOn) {
                    _checked.clear();
                  } else {
                    _checked.addAll(free.map(_key));
                  }
                }),
                child: Text(allOn ? 'Desmarcar todos' : 'Marcar todos'),
              ),
          ],
        ),
        if (events.isEmpty)
          Text(
            'No hay nada anotado en ese período.',
            style: theme.textTheme.bodySmall,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in events)
                  _EventRow(
                    event: e,
                    have: alreadyHave(e, have),
                    checked: _checked.contains(_key(e)),
                    onChanged: (v) => setState(() {
                      v ? _checked.add(_key(e)) : _checked.remove(_key(e));
                    }),
                  ),
              ],
            ),
          ),
        FilledButton(
          key: const Key('cal-add'),
          onPressed: selected == 0 || _busy ? null : () => _add(have),
          child: Text(
            selected == 0
                ? 'Agregar seleccionados'
                : 'Agregar seleccionados ($selected)',
          ),
        ),
        if (_busy) LinearProgressIndicator(color: scheme.primary),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.have,
    required this.checked,
    required this.onChanged,
  });

  final CalendarEvent event;
  final bool have;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = event;
    final when = e.allDay
        ? '${Fmt.day(e.start)} · todo el día (aviso a las 9:00)'
        : '${Fmt.day(e.start)} · ${Fmt.time(e.start)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: have ? Colors.green.shade50 : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          value: have || checked,
          onChanged: have ? null : (v) => onChanged(v ?? false),
          title: Text(
            e.title.isEmpty ? '(sin título)' : e.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: have ? Colors.green.shade900 : null,
            ),
          ),
          subtitle: Text(
            have
                ? '✓ Ya está en Recordame'
                : e.repeats
                ? '$when · se repite (se trae esta vez)'
                : when,
            style: TextStyle(color: have ? Colors.green.shade800 : null),
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.color,
    required this.background,
    required this.text,
  });

  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Más chico (pedido del usuario: ocupaba mucha pantalla).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

/// Botón con recuadro, el dibujo y el texto centrados en un renglón (la
/// letra se achica si no entra).
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size.fromHeight(40),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, maxLines: 1),
        ],
      ),
    ),
  );
}

/// Si Android puede frenar a Recordame, lo avisa con un botón para arreglarlo.
class _BatteryHint extends StatefulWidget {
  const _BatteryHint();

  @override
  State<_BatteryHint> createState() => _BatteryHintState();
}

class _BatteryHintState extends State<_BatteryHint>
    with WidgetsBindingObserver {
  bool _free = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final free = await AndroidDeviceCalendar.batteryFree();
    if (mounted) setState(() => _free = free);
  }

  @override
  Widget build(BuildContext context) {
    if (_free) return const SizedBox.shrink();
    const color = Color(0xFF6B5418);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para que funcione con la app cerrada, el teléfono no tiene que '
            'frenar a Recordame para ahorrar batería.',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            icon: const Icon(Icons.battery_saver_outlined),
            label: const Text('Evitar que el teléfono cierre la app'),
            onPressed: () async {
              await showBatteryHelp(context);
              _check();
            },
          ),
        ],
      ),
    );
  }
}

/// Muestra el calendario elegido con el nombre entero; al tocarlo abre la
/// lista completa (se puede deslizar) agrupada por cuenta.
class _CalendarPicker extends StatelessWidget {
  const _CalendarPicker({
    required this.calendars,
    required this.selected,
    required this.onPick,
  });

  final List<PhoneCalendar> calendars;
  final String? selected;
  final Future<void> Function(PhoneCalendar) onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = calendars.where((c) => c.id == selected).firstOrNull;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('cal-pick'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: current == null
              ? Row(
                  children: [
                    Icon(Icons.event, color: scheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Tocá para elegir')),
                    _change(scheme),
                  ],
                )
              : _CalendarText(calendar: current, trailing: _change(scheme)),
        ),
      ),
    );
  }

  /// "Cambiar": abajo del mail, como botoncito con recuadro.
  Widget _change(ColorScheme scheme) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: scheme.primary),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.swap_horiz, size: 16, color: scheme.primary),
        const SizedBox(width: 4),
        Text(
          'Cambiar calendario',
          style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    ),
  );

  Future<void> _open(BuildContext context) async {
    final byAccount = <String, List<PhoneCalendar>>{};
    for (final c in calendars) {
      byAccount.putIfAbsent(c.account, () => []).add(c);
    }
    final picked = await showAppSheet<PhoneCalendar>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final hint = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Elegí el calendario (${calendars.length})',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text('Deslizá para ver todos.', style: hint),
              for (final MapEntry(key: account, value: list)
                  in byAccount.entries) ...[
                const SizedBox(height: 16),
                Text(
                  account.isEmpty ? 'Sin cuenta' : account,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                for (final c in list)
                  RadioListTile<String>(
                    key: Key('cal-option-${c.id}'),
                    contentPadding: EdgeInsets.zero,
                    value: c.id,
                    // ignore: deprecated_member_use
                    groupValue: selected,
                    // ignore: deprecated_member_use
                    onChanged: (_) => Navigator.pop(context, c),
                    title: Text(c.name.isEmpty ? '(sin nombre)' : c.name),
                    subtitle: _tags(c).isEmpty ? null : Text(_tags(c)),
                  ),
              ],
              const SizedBox(height: 16),
              const _MissingHelp(),
            ],
          ),
        );
      },
    );
    if (picked != null) await onPick(picked);
  }
}

String _tags(PhoneCalendar c) => [
  if (c.primary) 'El principal',
  if (!c.writable) 'Solo para ver: se puede traer, no anotar',
  if (!c.synced) 'El teléfono no lo está sincronizando',
].join(' · ');

/// El calendario elegido (pedido del usuario): arriba el mail completo a lo
/// largo (se achica si no entra), abajo "El principal" y al final "Cambiar".
class _CalendarText extends StatelessWidget {
  const _CalendarText({required this.calendar, required this.trailing});

  final PhoneCalendar calendar;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tags = _tags(calendar);
    final mail = calendar.account.isNotEmpty ? calendar.account : calendar.name;
    final name = calendar.name.isNotEmpty && calendar.name != mail
        ? calendar.name
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.event, color: scheme.primary, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  mail.isEmpty ? '(sin nombre)' : mail,
                  maxLines: 1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (name != null)
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
          ),
        if (tags.isNotEmpty)
          Text(
            tags,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: calendar.primary
                  ? Colors.green.shade700
                  : scheme.onSurfaceVariant,
              fontWeight: calendar.primary ? FontWeight.w700 : null,
            ),
          ),
        const SizedBox(height: 4),
        trailing,
      ],
    );
  }
}

class _MissingHelp extends StatelessWidget {
  const _MissingHelp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text('¿No está el que buscás?', style: theme.textTheme.titleSmall),
          const Text(
            'Recordame ve los calendarios que el teléfono tiene guardados. '
            'Si uno se ve en Google Calendar pero no acá:',
          ),
          const Text(
            '•  Google Calendar → ☰ → Configuración → tocá ese calendario → '
            'prendé "Sincronizar". Esperá un minuto y volvé a entrar acá.',
          ),
          const Text(
            '•  Si es de Outlook o de la cuenta del trabajo con otra app, '
            'en esa app buscá "Sincronizar calendarios" con el teléfono.',
          ),
        ],
      ),
    );
  }
}
