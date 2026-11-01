import 'package:flutter/services.dart';

/// Un calendario del teléfono (por ejemplo el de la cuenta de Gmail).
class PhoneCalendar {
  const PhoneCalendar({
    required this.id,
    required this.name,
    required this.account,
    this.primary = false,
  });

  final String id;
  final String name;
  final String account;
  final bool primary;

  /// Cómo se muestra en la lista.
  String get label =>
      name == account || account.isEmpty ? name : '$name ($account)';
}

/// Una vez que toca un evento del calendario.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.allDay = false,
    this.repeats = false,
  });

  final String id;
  final String title;

  /// Hora local. En los de todo el día, ese día a las 9:00 (hora del aviso).
  final DateTime start;
  final bool allDay;
  final bool repeats;
}

/// El calendario que ya está en el teléfono (Google Calendar lo sincroniza
/// con la cuenta, así que lo que se anota acá aparece en la compu y al revés).
abstract class DeviceCalendar {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<List<PhoneCalendar>> calendars();
  Future<List<CalendarEvent>> events(
    String calendarId,
    DateTime from,
    DateTime to,
  );

  /// Crea un evento; devuelve su id.
  Future<String?> create(
    String calendarId,
    String title,
    DateTime start,
    String? rrule,
  );
  Future<bool> update(String id, String title, DateTime start, String? rrule);
  Future<void> delete(String id);
}

class AndroidDeviceCalendar implements DeviceCalendar {
  static const _channel = MethodChannel('recordame/calendario');

  @override
  Future<bool> hasPermission() async =>
      await _channel.invokeMethod<bool>('tienePermiso') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('pedirPermiso') ?? false;

  @override
  Future<List<PhoneCalendar>> calendars() async {
    final list = await _channel.invokeListMethod<Map>('calendarios') ?? [];
    return [
      for (final c in list)
        PhoneCalendar(
          id: '${c['id']}',
          name: '${c['nombre']}',
          account: '${c['cuenta']}',
          primary: c['principal'] == true,
        ),
    ];
  }

  @override
  Future<List<CalendarEvent>> events(
    String calendarId,
    DateTime from,
    DateTime to,
  ) async {
    final list =
        await _channel.invokeListMethod<Map>('eventos', {
          'calendario': int.parse(calendarId),
          'desde': from.millisecondsSinceEpoch,
          'hasta': to.millisecondsSinceEpoch,
        }) ??
        [];
    return [
      for (final e in list)
        CalendarEvent(
          id: '${e['id']}',
          title: '${e['titulo']}',
          start: eventStart(
            (e['inicio'] as num).toInt(),
            allDay: e['todoElDia'] == true,
          ),
          allDay: e['todoElDia'] == true,
          repeats: e['repite'] == true,
        ),
    ];
  }

  /// Los de todo el día vienen a las 0:00 UTC: se toma ese día a las 9:00.
  static DateTime eventStart(int millis, {required bool allDay}) {
    if (!allDay) return DateTime.fromMillisecondsSinceEpoch(millis);
    final utc = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day, 9);
  }

  @override
  Future<String?> create(
    String calendarId,
    String title,
    DateTime start,
    String? rrule,
  ) => _channel.invokeMethod<String>('crear', {
    'calendario': int.parse(calendarId),
    'titulo': title,
    'inicio': start.millisecondsSinceEpoch,
    'rrule': rrule,
  });

  @override
  Future<bool> update(
    String id,
    String title,
    DateTime start,
    String? rrule,
  ) async =>
      await _channel.invokeMethod<bool>('actualizar', {
        'id': id,
        'titulo': title,
        'inicio': start.millisecondsSinceEpoch,
        'rrule': rrule,
      }) ??
      false;

  @override
  Future<void> delete(String id) => _channel.invokeMethod('borrar', {'id': id});
}
