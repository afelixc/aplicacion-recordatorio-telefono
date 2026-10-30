import 'package:intl/intl.dart';

/// Formatos de fecha y hora en español.
class Fmt {
  static const locale = 'es_AR';

  /// "viernes 6 de noviembre"
  static String day(DateTime d) =>
      DateFormat("EEEE d 'de' MMMM", locale).format(d);

  /// "09:00"
  static String time(DateTime d) => DateFormat.Hm(locale).format(d);

  /// "hoy · 18:00", "mañana · 09:00" o "viernes 6 de noviembre · 09:00"
  static String when(DateTime d, {DateTime? now}) {
    now ??= DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
    final dayText = switch (diff) {
      0 => 'hoy',
      1 => 'mañana',
      -1 => 'ayer',
      _ => day(d),
    };
    return '$dayText · ${time(d)} h';
  }
}
