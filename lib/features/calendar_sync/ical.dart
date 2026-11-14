import 'package:http/http.dart' as http;

import 'device_calendar.dart';

/// El "link privado" de un calendario de Google (Configuración del
/// calendario → Integrar el calendario → Dirección secreta en formato iCal).
/// Recordame lo lee directo de Google, sin pasar por el teléfono: sirve
/// cuando el teléfono no recibe los eventos (pedido del usuario). Solo lee.

/// Arregla lo pegado: saca espacios y pasa `webcal://` a `https://`.
/// Devuelve null si no parece un link de calendario.
String? cleanIcalUrl(String raw) {
  var url = raw.trim();
  if (url.startsWith('webcal://')) url = 'https://${url.substring(9)}';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  if (!url.contains('.ics') && !uri.host.contains('calendar')) return null;
  return url;
}

/// Error al leer el link, con la explicación para el usuario.
class IcalError implements Exception {
  const IcalError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Baja el calendario y devuelve los eventos de [from] a [to].
Future<List<CalendarEvent>> fetchIcal(
  String url, {
  required DateTime from,
  required DateTime to,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404 || response.statusCode == 403) {
      throw const IcalError(
        'Google no reconoce ese link: puede que lo hayan cambiado '
        '("restablecer"). Copiá el link de nuevo.',
      );
    }
    if (response.statusCode != 200) {
      throw IcalError(
        'Google respondió con un error (${response.statusCode}).',
      );
    }
    final body = response.body;
    if (!body.contains('BEGIN:VCALENDAR')) {
      throw const IcalError(
        'Ese link no es de un calendario. Fijate que sea la "Dirección '
        'secreta en formato iCal".',
      );
    }
    return parseIcs(body, from: from, to: to);
  } on IcalError {
    rethrow;
  } catch (_) {
    throw const IcalError('No pude conectarme a Google. ¿Hay internet?');
  } finally {
    if (client == null) c.close();
  }
}

/// Lee el texto de un calendario (.ics). Los que se repiten traen solo la
/// próxima vez desde [from] (la siguiente llega cuando pase esa).
List<CalendarEvent> parseIcs(
  String text, {
  required DateTime from,
  required DateTime to,
}) {
  final lines = _unfold(text);
  final events = <_RawEvent>[];
  _RawEvent? cur;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      cur = _RawEvent();
    } else if (line == 'END:VEVENT') {
      if (cur != null) events.add(cur);
      cur = null;
    } else if (cur != null) {
      final colon = _valueStart(line);
      if (colon < 0) continue;
      final head = line.substring(0, colon);
      final value = line.substring(colon + 1);
      final parts = head.split(';');
      final name = parts.first.toUpperCase();
      final params = {
        for (final p in parts.skip(1))
          if (p.contains('='))
            p.substring(0, p.indexOf('=')).toUpperCase(): p.substring(
              p.indexOf('=') + 1,
            ),
      };
      switch (name) {
        case 'UID':
          cur.uid = value.trim();
        case 'SUMMARY':
          cur.title = _unescape(value);
        case 'DTSTART':
          cur.start = _parseTime(value, params);
          cur.allDay = params['VALUE'] == 'DATE' || !value.contains('T');
        case 'RRULE':
          cur.rule = value;
        case 'EXDATE':
          for (final v in value.split(',')) {
            final t = _parseTime(v, params);
            if (t != null) cur.exdates.add(t);
          }
        case 'RECURRENCE-ID':
          cur.recurrenceId = _parseTime(value, params);
        case 'STATUS':
          cur.cancelled = value.trim().toUpperCase() == 'CANCELLED';
      }
    }
  }

  // Las veces movidas o borradas de uno que se repite.
  final moved = <String, Set<DateTime>>{};
  for (final e in events) {
    if (e.recurrenceId != null && e.uid != null) {
      moved.putIfAbsent(e.uid!, () => {}).add(e.recurrenceId!);
    }
  }

  final out = <CalendarEvent>[];
  for (final e in events) {
    final start = e.start;
    if (e.uid == null || start == null || e.cancelled) continue;
    if (e.rule == null || e.recurrenceId != null) {
      if (!start.isBefore(from) && !start.isAfter(to)) {
        out.add(
          CalendarEvent(
            id: e.recurrenceId == null
                ? 'ical:${e.uid}'
                : 'ical:${e.uid}@${_stamp(start)}',
            title: e.title,
            start: start,
            allDay: e.allDay,
          ),
        );
      }
      continue;
    }
    final skip = {...e.exdates, ...?moved[e.uid]};
    final next = nextOccurrence(start, e.rule!, from: from, skip: skip);
    if (next != null && !next.isAfter(to)) {
      out.add(
        CalendarEvent(
          id: 'ical:${e.uid}@${_stamp(next)}',
          title: e.title,
          start: next,
          allDay: e.allDay,
          repeats: true,
        ),
      );
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// La próxima vez (desde [from]) de un evento que empezó en [start] y se
/// repite con [rule] (RRULE: FREQ, INTERVAL, COUNT, UNTIL y BYDAY semanal).
DateTime? nextOccurrence(
  DateTime start,
  String rule, {
  required DateTime from,
  Set<DateTime> skip = const {},
}) {
  final r = {
    for (final p in rule.split(';'))
      if (p.contains('='))
        p.substring(0, p.indexOf('=')).toUpperCase(): p.substring(
          p.indexOf('=') + 1,
        ),
  };
  final freq = r['FREQ'];
  final interval = int.tryParse(r['INTERVAL'] ?? '') ?? 1;
  final count = int.tryParse(r['COUNT'] ?? '');
  final until = r['UNTIL'] == null ? null : _parseTime(r['UNTIL']!, const {});
  const days = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};
  final byDay = <int>{
    for (final d in (r['BYDAY'] ?? '').split(','))
      if (days[d.trim().toUpperCase()] != null) days[d.trim().toUpperCase()]!,
  };

  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day, start.hour, start.minute);

  var n = 0;
  bool ok(DateTime t) {
    if (t.isBefore(start)) return false;
    n++;
    if (count != null && n > count) return false;
    return true;
  }

  for (var i = 0; i < 5000; i++) {
    final List<DateTime> candidates;
    switch (freq) {
      case 'DAILY':
        candidates = [
          at(DateTime(start.year, start.month, start.day + i * interval)),
        ];
      case 'WEEKLY':
        // Lunes de esa semana.
        final monday = DateTime(
          start.year,
          start.month,
          start.day - (start.weekday - 1) + 7 * i * interval,
        );
        final wanted = byDay.isEmpty ? {start.weekday} : byDay;
        candidates = [
          for (final d in (wanted.toList()..sort()))
            at(DateTime(monday.year, monday.month, monday.day + d - 1)),
        ];
      case 'MONTHLY':
        final m = DateTime(start.year, start.month + i * interval, start.day);
        // Si el mes no tiene ese día (31 de abril), ese mes no va.
        candidates = m.day == start.day ? [at(m)] : [];
      case 'YEARLY':
        final y = DateTime(start.year + i * interval, start.month, start.day);
        candidates = y.day == start.day ? [at(y)] : [];
      default:
        return null;
    }
    for (final t in candidates) {
      if (!ok(t)) {
        if (count != null && n > count) return null;
        continue;
      }
      if (until != null && t.isAfter(until)) return null;
      if (t.isBefore(from) || skip.contains(t)) continue;
      return t;
    }
  }
  return null;
}

class _RawEvent {
  String? uid;
  String title = '';
  DateTime? start;
  bool allDay = false;
  String? rule;
  DateTime? recurrenceId;
  bool cancelled = false;
  final Set<DateTime> exdates = {};
}

/// Los renglones largos vienen cortados: los que empiezan con espacio siguen
/// al anterior.
List<String> _unfold(String text) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else if (raw.isNotEmpty) {
      out.add(raw);
    }
  }
  return out;
}

/// Dónde empieza el valor: el primer ":" que no está entre comillas.
int _valueStart(String line) {
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') quoted = !quoted;
    if (c == ':' && !quoted) return i;
  }
  return -1;
}

String _unescape(String v) => v
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\')
    .trim();

/// "20261118T150000Z" (hora universal), "20261118T150000" (hora de acá) o
/// "20261118" (todo el día: ese día a las 9, como los del teléfono).
DateTime? _parseTime(String v, Map<String, String> params) {
  v = v.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$')
      .firstMatch(v);
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  if (m[4] == null) return DateTime(y, mo, d, 9);
  final h = int.parse(m[4]!);
  final mi = int.parse(m[5]!);
  final s = int.tryParse(m[6] ?? '') ?? 0;
  if (m[7] == 'Z') return DateTime.utc(y, mo, d, h, mi, s).toLocal();
  return DateTime(y, mo, d, h, mi, s);
}

String _stamp(DateTime t) =>
    '${t.year}${t.month.toString().padLeft(2, '0')}'
    '${t.day.toString().padLeft(2, '0')}'
    '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
