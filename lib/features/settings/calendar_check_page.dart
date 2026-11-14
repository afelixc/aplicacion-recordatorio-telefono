import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatting.dart';
import '../../data/reminder.dart';
import '../calendar_sync/calendar_sync.dart';
import '../calendar_sync/device_calendar.dart';
import '../calendar_sync/ical.dart';

/// Lo que el teléfono tiene en cada calendario y si ya está en Recordame.
/// Sirve para ver por qué algo de Google Calendar no llegó (pedido del
/// usuario): ya estaba antes de prender el 4, está en otro calendario o el
/// teléfono no lo tiene.
class CalendarCheckPage extends StatefulWidget {
  const CalendarCheckPage({super.key, required this.sync});

  final CalendarSync sync;

  /// Desde cuándo y hasta cuándo se mira.
  static const back = Duration(days: 1);
  static const ahead = Duration(days: 60);

  @override
  State<CalendarCheckPage> createState() => _CalendarCheckPageState();
}

/// Cómo está un evento del calendario elegido.
enum EventState {
  /// Ya está en Recordame.
  here,

  /// Ya estaba en el calendario cuando se prendió el 4: no se trae solo.
  before,

  /// Es nuevo: se trae al abrir o volver a la app (o con la app cerrada).
  coming,

  /// El 4 está apagado: solo se trae a mano (con el 3).
  manual,
}

EventState eventState(
  CalendarEvent e,
  List<Reminder> have, {
  required bool auto,
  required Set<String> known,
}) {
  if (alreadyHave(e, have)) return EventState.here;
  if (!auto) return EventState.manual;
  return known.contains(e.id) ? EventState.before : EventState.coming;
}

class _CalendarCheckPageState extends State<CalendarCheckPage> {
  bool _loading = true;
  String? _error;
  List<PhoneCalendar> _calendars = const [];

  /// Eventos de cada calendario (id → eventos), del más cercano al más lejano.
  final Map<String, List<CalendarEvent>> _events = {};
  List<Reminder> _have = const [];

  /// Lo que se lee del link privado de Google (null = sin link).
  List<CalendarEvent>? _ical;
  String? _icalError;
  String? _message;
  bool _busy = false;

  CalendarSync get _sync => widget.sync;

  @override
  void initState() {
    super.initState();
    // Lee el repositorio de AppScope: recién después del primer cuadro.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = AppScope.of(context).reminders;
      final now = DateTime.now();
      final from = now.subtract(CalendarCheckPage.back);
      final to = now.add(CalendarCheckPage.ahead);
      final calendars = await _sync.calendar.calendars();
      _events.clear();
      for (final c in calendars) {
        final list = await _sync.calendar.events(c.id, from, to);
        list.sort((a, b) => a.start.compareTo(b.start));
        _events[c.id] = list;
      }
      _have = await repo.watchAll().first;
      _ical = null;
      _icalError = null;
      if (_sync.settings.icalUrl != null) {
        try {
          _ical = await _sync.icalReader(_sync.settings.icalUrl!, from, to);
        } catch (e) {
          _icalError = '$e';
        }
      }
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pude leer los calendarios del teléfono ($e).';
        _loading = false;
      });
    }
  }

  /// Trae a Recordame los del calendario elegido que todavía no están.
  Future<void> _bringMissing(List<CalendarEvent> missing) async {
    final repo = AppScope.of(context).reminders;
    setState(() => _busy = true);
    final added = await _sync.import(missing, repo);
    await _sync.settings.addCalendarKnown(missing.map((e) => e.id));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = added == 1
          ? 'Traje 1 a Recordame.'
          : 'Traje $added a Recordame.';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Qué ve el teléfono?'),
        actions: [
          IconButton(
            key: const Key('check-reload'),
            tooltip: 'Volver a mirar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Esto es lo que el teléfono tiene en sus calendarios desde '
                  'ayer y por 60 días, que es lo único que Recordame puede '
                  'leer. Si algo está en Google Calendar pero no aparece '
                  'acá, el teléfono no lo está recibiendo.',
                  style: hint,
                ),
                const SizedBox(height: 6),
                Text(
                  'Las "Tareas" de Google (las del círculo con tilde) no son '
                  'eventos: Google no se las pasa a ninguna otra app.',
                  style: hint,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '✓ $_message',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ..._link(theme),
                ..._chosen(theme),
                const SizedBox(height: 16),
                ..._others(theme),
              ],
            ),
    );
  }

  /// Lo que se lee del link privado de Google (el 5), si está puesto.
  List<Widget> _link(ThemeData theme) {
    if (_sync.settings.icalUrl == null) return const [];
    final known = _sync.settings.calendarKnown;
    final events = _ical ?? const [];
    final missing = [
      for (final e in events)
        if (eventState(e, _have, auto: true, known: known) != EventState.here &&
            e.start.isAfter(DateTime.now()))
          e,
    ];
    return [
      Text(
        'DESDE GOOGLE, CON EL LINK PRIVADO (EL 5)',
        style: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      if (_icalError == null)
        Text(
          'Calendario del link: ${lastIcalName ?? '(sin nombre)'} · '
          '$lastIcalTotal ${lastIcalTotal == 1 ? 'evento' : 'eventos'} en '
          'total (también los pasados).',
          key: const Key('check-ical-name'),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      const SizedBox(height: 6),
      if (_icalError != null)
        _Warn(_icalError!, theme.colorScheme)
      else if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Google no tiene nada anotado para estos días.'),
        )
      else
        for (final e in events)
          _EventTile(
            event: e,
            state: eventState(e, _have, auto: true, known: known),
            link: true,
          ),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: 6),
        FilledButton.icon(
          key: const Key('check-bring-ical'),
          icon: const Icon(Icons.download),
          label: Text(
            missing.length == 1
                ? 'Traer el que falta'
                : 'Traer los ${missing.length} que faltan',
          ),
          onPressed: _busy ? null : () => _bringMissing(missing),
        ),
      ],
      const SizedBox(height: 16),
    ];
  }

  /// El calendario elegido en el 1, con el estado de cada evento.
  List<Widget> _chosen(ThemeData theme) {
    final scheme = theme.colorScheme;
    final s = _sync.settings;
    final id = s.calendarId;
    final cal = _calendars.where((c) => c.id == id).firstOrNull;
    if (cal == null) {
      return [const Text('Todavía no elegiste un calendario en el 1.')];
    }
    final events = _events[cal.id] ?? const [];
    final states = {
      for (final e in events)
        e: eventState(e, _have, auto: s.calendarAuto, known: s.calendarKnown),
    };
    final missing = [
      for (final e in events)
        if (states[e] != EventState.here && e.start.isAfter(DateTime.now())) e,
    ];
    return [
      _Title('El que usás (el 1)', cal),
      if (!cal.synced)
        _Warn(
          'El teléfono NO está sincronizando este calendario: lo nuevo de '
          'Google no le llega. Activalo en Ajustes del teléfono → Cuentas → '
          'Google → ${cal.account} → Calendario.',
          scheme,
        ),
      if (events.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'El teléfono no tiene nada en este calendario para estos días.',
          ),
        )
      else
        for (final e in events) _EventTile(event: e, state: states[e]!),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('check-bring'),
          icon: const Icon(Icons.download),
          label: Text(
            missing.length == 1
                ? 'Traer el que falta'
                : 'Traer los ${missing.length} que faltan',
          ),
          onPressed: _busy ? null : () => _bringMissing(missing),
        ),
      ],
    ];
  }

  /// Los demás calendarios: por si lo que falta está en otro.
  List<Widget> _others(ThemeData theme) {
    final others = [
      for (final c in _calendars)
        if (c.id != _sync.settings.calendarId) c,
    ];
    if (others.isEmpty) return const [];
    return [
      Text(
        'OTROS CALENDARIOS DEL TELÉFONO',
        style: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        'Si lo que falta aparece acá, está en otro calendario: elegí ese en '
        'el 1, o anotalo en el que usás.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 6),
      for (final c in others)
        _OtherCalendar(calendar: c, events: _events[c.id]),
    ];
  }
}

class _Title extends StatelessWidget {
  const _Title(this.label, this.calendar);

  final String label;
  final PhoneCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mail = calendar.account.isNotEmpty ? calendar.account : calendar.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelLarge?.copyWith(
            letterSpacing: 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            mail,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        if (calendar.name != mail && calendar.name.isNotEmpty)
          Text(calendar.name, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn(this.text, this.scheme);

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.state,
    this.link = false,
  });

  final CalendarEvent event;
  final EventState state;

  /// Viene del link privado (no del teléfono).
  final bool link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (state) {
      EventState.here => (
        Icons.check_circle,
        Colors.green.shade700,
        'Ya está en Recordame',
      ),
      EventState.before => (
        Icons.history,
        Colors.orange.shade800,
        link
            ? 'Ya estaba al pegar el link: no se trae solo'
            : 'Ya estaba antes de prender el 4: no se trae solo',
      ),
      EventState.coming => (
        Icons.schedule,
        theme.colorScheme.primary,
        'Nuevo: se trae al volver a la app',
      ),
      EventState.manual => (
        Icons.pan_tool_alt_outlined,
        theme.colorScheme.onSurfaceVariant,
        'El 4 está apagado: se trae con el 3',
      ),
    };
    final title = event.title.trim().isEmpty
        ? '(Sin título)'
        : event.title.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    if (event.allDay)
                      '${Fmt.day(event.start)} · todo el día'
                    else
                      Fmt.when(event.start),
                    if (event.repeats) 'se repite',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherCalendar extends StatelessWidget {
  const _OtherCalendar({required this.calendar, required this.events});

  final PhoneCalendar calendar;
  final List<CalendarEvent>? events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = events ?? const [];
    final name = calendar.name.isEmpty ? '(sin nombre)' : calendar.name;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExpansionTile(
        dense: true,
        shape: const Border(),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (calendar.account.isNotEmpty && calendar.account != name)
              calendar.account,
            list.isEmpty
                ? 'nada estos días'
                : list.length == 1
                ? '1 evento'
                : '${list.length} eventos',
            if (!calendar.synced) 'no se sincroniza',
          ].join(' · '),
          maxLines: 2,
        ),
        children: [
          for (final e in list.take(30))
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                e.title.trim().isEmpty ? '(Sin título)' : e.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(Fmt.when(e.start)),
            ),
        ],
      ),
    );
  }
}
