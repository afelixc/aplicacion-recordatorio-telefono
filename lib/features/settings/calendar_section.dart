import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../core/settings.dart';
import '../../data/reminder.dart';
import '../calendar_sync/calendar_sync.dart';
import '../calendar_sync/device_calendar.dart';
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
          (c) => c.primary,
          orElse: () => list.first,
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

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 5),
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
    final choice = pending == 0
        ? _Send.onlyNew
        : await showDialog<_Send>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Enviar al calendario'),
              content: Text(
                'Desde ahora, lo que cargues en Recordame va a aparecer en tu '
                'calendario.\n\nYa tenés $pending recordatorios pendientes '
                'cargados de antes. ¿Qué hago con esos?',
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _Send.all),
                    child: Text('Mandar también esos $pending'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, _Send.onlyNew),
                    child: const Text(
                      'Esos no, solo lo que cargue desde ahora',
                      textAlign: TextAlign.center,
                    ),
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

  Future<void> _toggleAuto(bool on) async {
    if (on) {
      await widget.sync.startAuto();
      if (mounted) {
        _say(
          'Listo ✓ Lo nuevo que anotes en el calendario va a llegar a Recordame.',
        );
      }
    } else {
      await _settings.setCalendarAuto(false);
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
    final both = s.calendarSend && s.calendarAuto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
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
              DropdownButtonFormField<String>(
                key: const Key('cal-pick'),
                initialValue: calendars.any((c) => c.id == s.calendarId)
                    ? s.calendarId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Los calendarios de este teléfono',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in calendars)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        c.primary ? '${c.label} · el principal' : c.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) async {
                  final c = calendars.firstWhere((c) => c.id == id);
                  await s.setCalendar(c.id, c.label);
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
              key: const Key('cal-send'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Enviar mis recordatorios al calendario'),
              subtitle: Text(
                s.calendarSend
                    ? 'Prendido: lo que cargás, cambiás o borrás en Recordame '
                          'aparece en ${s.calendarName ?? 'tu calendario'}.'
                    : 'Apagado: el calendario no se toca.',
              ),
              value: s.calendarSend,
              onChanged: s.calendarId == null || _busy ? null : _toggleSend,
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
              key: const Key('cal-auto'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Traer lo nuevo automáticamente'),
              subtitle: Text(
                s.calendarAuto
                    ? 'Prendido: lo nuevo que anotes en '
                          '${s.calendarName ?? 'tu calendario'}, aunque sea '
                          'desde la compu, aparece en Recordame y te avisa. '
                          'Se revisa cada vez que abrís la app.'
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
